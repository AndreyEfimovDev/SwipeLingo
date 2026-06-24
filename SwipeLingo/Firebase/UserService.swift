import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// MARK: - UserService
//
// Manages the Firestore user document (users/{uid}) and local subscription cache.
//
// Responsibilities:
//  • createOrUpdateUser — upsert on first sign-in / provider link
//  • syncSubscription   — fetch Firestore subscription and update local cache
//  • effectivePlan      — offline-safe plan resolution with grace period
//
// Subscription logic:
//  • Free → Paid : 7-day Pro trial (Constants.trialDurationDays), status=trial, no grace period
//  • Paid → Paid : direct activation, status=active, endDate=now+1yr
//  • Paid → Free : cancel — status=cancelled, plan+endDate unchanged, grace period applies
//
// Local cache keys → Constants.StorageKey
// Grace period: Constants.subscriptionGracePeriodDays days (paid only, not trial).

@Observable
@MainActor
final class UserService {

    private(set) var isLoading = false

    private var db: Firestore { Firestore.firestore() }

    // MARK: - Upsert user document

    /// Creates the Firestore user document on first sign-in.
    /// On subsequent sign-ins updates provider + displayName + updatedAt only (preserves subscription).
    func createOrUpdateUser(
        _ firebaseUser: FirebaseAuth.User,
        nativeLanguage: String = "",
        cefrLevel: String = ""
    ) async {
        let ref = db.collection("users").document(firebaseUser.uid)
        do {
            let snapshot = try await ref.getDocument()
            if snapshot.exists {
                // Update mutable fields only — do NOT overwrite subscription.
                // nativeLanguage backfills accounts created before onboarding set the preference.
                var updates: [String: Any] = [
                    "authProvider": AuthProviderID.from(firebaseUser),
                    "displayName":  firebaseUser.displayName ?? "",
                    "email":        firebaseUser.isAnonymous ? NSNull() : (firebaseUser.email as Any),
                    "updatedAt":    Timestamp(date: Date())
                ]
                if !nativeLanguage.isEmpty { updates["nativeLanguage"] = nativeLanguage }
                try await ref.updateData(updates)
                log("[UserService] User document updated: \(firebaseUser.uid)", level: .info)
            } else {
                // First sign-in — create full document
                let doc = UserFirestoreDocument.make(
                    from: firebaseUser,
                    nativeLanguage: nativeLanguage,
                    cefrLevel: cefrLevel
                )
                try ref.setData(from: doc)
                log("[UserService] User document created: \(firebaseUser.uid)", level: .info)
                // Cache Free plan as default
                cachePlan(.free, status: .active, expiry: nil)
            }
        } catch {
            log("[UserService] createOrUpdateUser failed: \(error)", level: .error)
        }
    }

    // MARK: - Sync subscription

    /// Fetches subscription from Firestore and updates local AppStorage cache.
    /// Call on app launch (when network is available) and after plan changes.
    func syncSubscription(for uid: String) async {
        guard FirebaseApp.app() != nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db.collection("users").document(uid).getDocument()
            guard snapshot.exists,
                  let doc = try? snapshot.data(as: UserFirestoreDocument.self)
            else { return }

            let sub          = doc.subscription
            let plan         = AccessTier(rawValue: sub.plan)          ?? .free
            let status       = SubscriptionStatus(rawValue: sub.status) ?? .active
            let billingCycle = BillingCycle(rawValue: sub.billingCycle) ?? .none
            // Trial uses trialEndDate as expiry; paid uses endDate
            let expiry = status == .trial ? sub.trialEndDate : sub.endDate

            cachePlan(plan, status: status, expiry: expiry, billingCycle: billingCycle)

            if let pendingRaw = sub.pendingPlan, let pendingPlan = AccessTier(rawValue: pendingRaw) {
                let pendingCycle = sub.pendingBillingCycle.flatMap { BillingCycle(rawValue: $0) } ?? .none
                cachePending(plan: pendingPlan, billingCycle: pendingCycle)
            } else {
                clearPending()
            }

            log("[UserService] Subscription synced: \(plan.rawValue) / \(status.rawValue)", level: .info)

        } catch {
            log("[UserService] syncSubscription failed: \(error)", level: .error)
        }
    }

    // MARK: - Effective plan (offline-safe)

    /// Resolves the user's current plan from local cache, applying grace period.
    /// - If cached plan has expired + grace period passed → returns .free
    /// - Otherwise returns cached plan (works offline)
    func effectivePlan() -> AccessTier {
        let cached = UserDefaults.standard.string(forKey: Constants.StorageKey.userPlan)
            .flatMap { AccessTier(rawValue: $0) } ?? .free

        guard cached != .free else { return .free }

        let statusRaw = UserDefaults.standard.string(forKey: Constants.StorageKey.cachedPlanStatus) ?? ""
        let isTrial   = statusRaw == SubscriptionStatus.trial.rawValue

        let expiryTS = UserDefaults.standard.double(forKey: Constants.StorageKey.cachedPlanExpiry)
        guard expiryTS > 0 else { return cached } // no expiry → subscription active indefinitely

        let expiry = Date(timeIntervalSince1970: expiryTS)

        if isTrial {
            // Trial: hard cutoff at trialEndDate, no grace period
            if Date() > expiry {
                cachePlan(.free, status: .expired, expiry: nil)
                log("[UserService] Trial expired → downgraded to Free", level: .info)
                return .free
            }
            return cached
        }

        // Paid subscription: apply grace period
        let graceCutoff = expiry.addingTimeInterval(
            Double(Constants.subscriptionGracePeriodDays) * 86_400
        )
        if Date() > graceCutoff {
            cachePlan(.free, status: .expired, expiry: nil)
            log("[UserService] Subscription expired + grace period over → downgraded to Free", level: .info)
            return .free
        }
        if Date() > expiry {
            log("[UserService] Subscription expired, grace period active (\(Constants.subscriptionGracePeriodDays)d remaining)", level: .info)
        }
        return cached
    }

    // MARK: - Update subscription

    /// Simulated purchase: activates subscription, writes PaymentRecord + PlanHistoryRecord to Firestore.
    /// cardLast4 — last 4 digits of the fake card.
    @discardableResult
    func purchaseSubscription(
        plan: AccessTier,
        billingCycle: BillingCycle,
        amount: Double,
        cardLast4: String,
        currency: String = "USD",
        for uid: String
    ) async -> Bool {
        let currentPlanRaw = UserDefaults.standard.string(forKey: Constants.StorageKey.userPlan) ?? AccessTier.free.rawValue
        let currentPlan    = AccessTier(rawValue: currentPlanRaw) ?? .free

        let now      = Date()
        let days: Double = billingCycle == .monthly ? 30 : 365
        let endDate  = now.addingTimeInterval(days * 86_400)

        let ref = db.collection("users").document(uid)

        let subscriptionUpdate: [String: Any] = [
            "subscription.plan":                plan.rawValue,
            "subscription.billingCycle":        billingCycle.rawValue,
            "subscription.status":              SubscriptionStatus.active.rawValue,
            "subscription.startDate":           Timestamp(date: now),
            "subscription.endDate":             Timestamp(date: endDate),
            "subscription.trialEndDate":        NSNull(),
            "subscription.amount":              amount,
            "subscription.currency":            currency,
            "subscription.pendingPlan":         NSNull(),
            "subscription.pendingBillingCycle": NSNull(),
            "updatedAt":                        Timestamp(date: now)
        ]

        let reason: String
        if currentPlan == .free      { reason = "upgrade" }
        else if plan.rank > currentPlan.rank { reason = "upgrade" }
        else if plan.rank < currentPlan.rank { reason = "downgrade" }
        else                         { reason = "cycle_change" }

        let paymentId = UUID().uuidString
        let payment   = PaymentRecord(
            id: paymentId, date: now, amount: amount, currency: currency,
            plan: plan.rawValue, billingCycle: billingCycle.rawValue,
            paymentMethod: "card", last4: cardLast4,
            status: PaymentStatus.success.rawValue
        )

        let historyId = UUID().uuidString
        let history   = PlanHistoryRecord(
            id: historyId, date: now,
            fromPlan: currentPlan.rawValue, toPlan: plan.rawValue, reason: reason
        )

        do {
            try await ref.updateData(subscriptionUpdate)
            try ref.collection("paymentHistory").document(paymentId).setData(from: payment)
            try ref.collection("planHistory").document(historyId).setData(from: history)
            cachePlan(plan, status: .active, expiry: endDate, billingCycle: billingCycle)
            clearPending()
            log("[UserService] Subscription purchased: \(plan.rawValue)/\(billingCycle.rawValue)", level: .info)
            return true
        } catch {
            log("[UserService] purchaseSubscription failed: \(error)", level: .error)
            return false
        }
    }

    /// Loads payment history from Firestore, sorted newest first.
    func loadPaymentHistory(for uid: String) async -> [PaymentRecord] {
        do {
            let snap = try await db.collection("users").document(uid)
                .collection("paymentHistory")
                .order(by: "date", descending: true)
                .getDocuments()
            return snap.documents.compactMap { try? $0.data(as: PaymentRecord.self) }
        } catch {
            log("[UserService] loadPaymentHistory failed: \(error)", level: .error)
            return []
        }
    }

    /// Schedules a downgrade — keeps current plan active until endDate, sets pending to new plan/cycle.
    func scheduleDowngrade(plan: AccessTier, billingCycle: BillingCycle, for uid: String) async {
        let data: [String: Any] = [
            "subscription.pendingPlan":         plan.rawValue,
            "subscription.pendingBillingCycle": billingCycle.rawValue,
            "updatedAt":                        Timestamp(date: Date())
        ]
        do {
            try await db.collection("users").document(uid).updateData(data)
            cachePending(plan: plan, billingCycle: billingCycle)
            log("[UserService] Downgrade scheduled → \(plan.rawValue)/\(billingCycle.rawValue)", level: .info)
        } catch {
            log("[UserService] scheduleDowngrade failed: \(error)", level: .error)
        }
    }

    /// Cancels subscription — keeps access until endDate, updates status to cancelled.
    func cancelSubscription(for uid: String) async {
        let currentPlanRaw = UserDefaults.standard.string(forKey: Constants.StorageKey.userPlan) ?? AccessTier.free.rawValue
        let currentPlan    = AccessTier(rawValue: currentPlanRaw) ?? .free
        await cancelSubscription(for: uid, currentPlan: currentPlan)
    }

    @discardableResult
    func updateSubscription(plan: AccessTier, for uid: String) async -> Bool {
        let currentPlanRaw = UserDefaults.standard.string(forKey: Constants.StorageKey.userPlan) ?? AccessTier.free.rawValue
        let currentPlan    = AccessTier(rawValue: currentPlanRaw) ?? .free

        if plan == .free && currentPlan != .free {
            await cancelSubscription(for: uid, currentPlan: currentPlan)
        } else if plan != .free && currentPlan == .free {
            return await startTrial(pendingPlan: plan, for: uid)
        } else if plan != .free && currentPlan != .free {
            await activateSubscription(plan: plan, for: uid)
        }
        return true
    }

    // Trial always gives Pro access to showcase full feature set.
    // pendingPlan records what the user intends to pay for after trial.
    // Returns false if trial was already used (trialEndDate exists in Firestore).
    func startTrial(pendingPlan: AccessTier, for uid: String) async -> Bool {
        let ref = db.collection("users").document(uid)
        do {
            let snapshot = try await ref.getDocument()
            if let doc = try? snapshot.data(as: UserFirestoreDocument.self),
               doc.subscription.trialEndDate != nil {
                log("[UserService] startTrial blocked — trial already used for \(uid)", level: .info)
                return false
            }

            let now      = Date()
            let trialEnd = now.addingTimeInterval(Double(Constants.trialDurationDays) * 86_400)

            let data: [String: Any] = [
                "subscription.plan":               AccessTier.pro.rawValue,
                "subscription.billingCycle":       BillingCycle.none.rawValue,
                "subscription.status":             SubscriptionStatus.trial.rawValue,
                "subscription.startDate":          Timestamp(date: now),
                "subscription.endDate":            NSNull(),
                "subscription.trialEndDate":       Timestamp(date: trialEnd),
                "subscription.pendingPlan":        pendingPlan.rawValue,
                "subscription.pendingBillingCycle": BillingCycle.yearly.rawValue,
                "updatedAt":                       Timestamp(date: now)
            ]
            try await ref.updateData(data)
            cachePlan(.pro, status: .trial, expiry: trialEnd)
            log("[UserService] Trial started → Pro until \(trialEnd), pending: \(pendingPlan.rawValue)", level: .info)
            return true
        } catch {
            log("[UserService] startTrial failed: \(error)", level: .error)
            return false
        }
    }

    private func activateSubscription(plan: AccessTier, for uid: String) async {
        let now     = Date()
        let endDate = now.addingTimeInterval(365 * 86_400)

        let data: [String: Any] = [
            "subscription.plan":               plan.rawValue,
            "subscription.billingCycle":       BillingCycle.yearly.rawValue,
            "subscription.status":             SubscriptionStatus.active.rawValue,
            "subscription.startDate":          Timestamp(date: now),
            "subscription.endDate":            Timestamp(date: endDate),
            "subscription.trialEndDate":       NSNull(),
            "subscription.pendingPlan":        NSNull(),
            "subscription.pendingBillingCycle": NSNull(),
            "updatedAt":                       Timestamp(date: now)
        ]
        do {
            try await db.collection("users").document(uid).updateData(data)
            cachePlan(plan, status: .active, expiry: endDate)
            log("[UserService] Subscription activated → \(plan.rawValue)", level: .info)
        } catch {
            log("[UserService] activateSubscription failed: \(error)", level: .error)
        }
    }

    func cancelSubscription(for uid: String, currentPlan: AccessTier) async {
        // Keep plan + endDate intact — user retains access until expiry.
        // Only update status and pendingPlan.
        let data: [String: Any] = [
            "subscription.status":            SubscriptionStatus.cancelled.rawValue,
            "subscription.pendingPlan":       AccessTier.free.rawValue,
            "subscription.pendingBillingCycle": BillingCycle.none.rawValue,
            "updatedAt":                      Timestamp(date: Date())
        ]
        do {
            try await db.collection("users").document(uid).updateData(data)
            // Keep current plan in local cache, only update status
            let expiryTS = UserDefaults.standard.double(forKey: Constants.StorageKey.cachedPlanExpiry)
            let expiry   = expiryTS > 0 ? Date(timeIntervalSince1970: expiryTS) : nil
            cachePlan(currentPlan, status: .cancelled, expiry: expiry)
            cachePending(plan: .free, billingCycle: .none)
            log("[UserService] Subscription cancelled — access until \(expiry?.description ?? "unknown")", level: .info)
        } catch {
            log("[UserService] cancelSubscription failed: \(error)", level: .error)
        }
    }

    // MARK: - Update notification email

    func updateNotificationEmail(_ email: String, for uid: String) async {
        do {
            try await db.collection("users").document(uid).updateData([
                "notificationEmail": email.isEmpty ? NSNull() : email,
                "updatedAt":         Timestamp(date: Date())
            ])
            log("[UserService] Notification email updated", level: .info)
        } catch {
            log("[UserService] updateNotificationEmail failed: \(error)", level: .error)
        }
    }

    // MARK: - Local cache

    private func cachePending(plan: AccessTier, billingCycle: BillingCycle) {
        UserDefaults.standard.set(plan.rawValue,         forKey: Constants.StorageKey.cachedPendingPlan)
        UserDefaults.standard.set(billingCycle.rawValue, forKey: Constants.StorageKey.cachedPendingCycle)
    }

    private func clearPending() {
        UserDefaults.standard.removeObject(forKey: Constants.StorageKey.cachedPendingPlan)
        UserDefaults.standard.removeObject(forKey: Constants.StorageKey.cachedPendingCycle)
    }

    private func cachePlan(_ plan: AccessTier, status: SubscriptionStatus, expiry: Date?, billingCycle: BillingCycle = .none) {
        UserDefaults.standard.set(plan.rawValue,          forKey: Constants.StorageKey.userPlan)
        UserDefaults.standard.set(status.rawValue,        forKey: Constants.StorageKey.cachedPlanStatus)
        UserDefaults.standard.set(billingCycle.rawValue,  forKey: Constants.StorageKey.cachedBillingCycle)
        if let expiry {
            UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: Constants.StorageKey.cachedPlanExpiry)
        } else {
            UserDefaults.standard.removeObject(forKey: Constants.StorageKey.cachedPlanExpiry)
        }
    }
}
