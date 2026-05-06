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
// Local cache keys → Constants.StorageKey
// Grace period: Constants.subscriptionGracePeriodDays days after expiry before Free downgrade.

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

            cachePlan(plan, status: status, expiry: sub.endDate)
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

        // Check expiry from cache
        let expiryTS = UserDefaults.standard.double(forKey: Constants.StorageKey.cachedPlanExpiry)
        guard expiryTS > 0 else { return cached } // no expiry set → subscription active

        let expiry = Date(timeIntervalSince1970: expiryTS)
        let graceCutoff = expiry.addingTimeInterval(
            Double(Constants.subscriptionGracePeriodDays) * 86_400
        )

        if Date() > graceCutoff {
            // Grace period over — downgrade to Free and clear cache
            cachePlan(.free, status: .expired, expiry: nil)
            log("[UserService] Subscription expired + grace period over → downgraded to Free", level: .info)
            return .free
        }

        if Date() > expiry {
            log("[UserService] Subscription expired, grace period active (\(Constants.subscriptionGracePeriodDays)d remaining)", level: .info)
        }

        return cached
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
