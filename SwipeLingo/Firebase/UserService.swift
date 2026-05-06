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
                // Update mutable fields only — do NOT overwrite subscription
                let updates: [String: Any] = [
                    "authProvider": AuthProviderID.from(firebaseUser),
                    "displayName":  firebaseUser.displayName ?? "",
                    "email":        firebaseUser.isAnonymous ? NSNull() : (firebaseUser.email as Any),
                    "updatedAt":    Timestamp(date: Date())
                ]
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

            let sub    = doc.subscription
            let plan   = AccessTier(rawValue: sub.plan)   ?? .free
            let status = SubscriptionStatus(rawValue: sub.status) ?? .active
            // Trial uses trialEndDate as expiry; paid uses endDate
            let expiry = status == .trial ? sub.trialEndDate : sub.endDate

            cachePlan(plan, status: status, expiry: expiry)
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

    /// Writes the plan change to Firestore and updates local cache.
    /// DEBUG stub — no real payment. Replace with server-side write after StoreKit integration.
    ///
    /// Logic:
    ///   Free → Paid  : 7-day Pro trial (Constants.trialDurationDays), pendingPlan=selectedPlan
    ///   Paid → Paid  : direct activation, status=active, endDate=now+1yr
    ///   Paid → Free  : cancel — status=cancelled, plan+endDate unchanged
    /// Returns false if trial was already used (Firestore has a prior trialEndDate).
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
    private func startTrial(pendingPlan: AccessTier, for uid: String) async -> Bool {
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

    private func cancelSubscription(for uid: String, currentPlan: AccessTier) async {
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

    private func cachePlan(_ plan: AccessTier, status: SubscriptionStatus, expiry: Date?) {
        UserDefaults.standard.set(plan.rawValue,   forKey: Constants.StorageKey.userPlan)
        UserDefaults.standard.set(status.rawValue, forKey: Constants.StorageKey.cachedPlanStatus)
        if let expiry {
            UserDefaults.standard.set(
                expiry.timeIntervalSince1970,
                forKey: Constants.StorageKey.cachedPlanExpiry
            )
        } else {
            UserDefaults.standard.removeObject(forKey: Constants.StorageKey.cachedPlanExpiry)
        }
    }
}
