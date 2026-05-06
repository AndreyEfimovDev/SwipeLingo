import Foundation
import FirebaseAuth

// MARK: - UserFirestoreDocument
// Firestore: users/{uid}

struct UserFirestoreDocument: Codable {
    var uid:               String
    var email:             String?   // provider email (Google/Apple/Email) — не редактируется
    var notificationEmail: String?   // email для рассылки — редактируется пользователем
    var displayName:       String
    var nativeLanguage:    String
    var cefrLevel:         String
    var authProvider:      String    // "anonymous" | "email" | "google" | "apple"
    var createdAt:         Date
    var updatedAt:         Date
    var subscription:      SubscriptionData

    // MARK: - SubscriptionData (embedded)

    struct SubscriptionData: Codable {
        var plan:               String  // AccessTier.rawValue
        var billingCycle:       String  // BillingCycle.rawValue
        var status:             String  // SubscriptionStatus.rawValue
        var startDate:          Date?
        var endDate:            Date?
        var trialEndDate:       Date?
        var amount:             Double?
        var currency:           String? // "EUR" | "USD" | "RUB"
        var pendingPlan:        String? // plan ожидающий вступления в силу (при downgrade)
        var pendingBillingCycle: String?

        static var free: SubscriptionData {
            SubscriptionData(
                plan:               AccessTier.free.rawValue,
                billingCycle:       BillingCycle.none.rawValue,
                status:             SubscriptionStatus.active.rawValue
            )
        }
    }

    // MARK: - Factory

    static func make(from user: FirebaseAuth.User, nativeLanguage: String, cefrLevel: String) -> UserFirestoreDocument {
        UserFirestoreDocument(
            uid:               user.uid,
            email:             user.isAnonymous ? nil : user.email,
            notificationEmail: nil,
            displayName:       user.displayName ?? "",
            nativeLanguage:    nativeLanguage,
            cefrLevel:         cefrLevel,
            authProvider:      AuthProviderID.from(user),
            createdAt:         Date(),
            updatedAt:         Date(),
            subscription:      .free
        )
    }
}

// MARK: - BillingCycle

enum BillingCycle: String, Codable, CaseIterable {
    case none    = "none"
    case monthly = "monthly"
    case yearly  = "yearly"

    var displayName: String {
        switch self {
        case .none:    return "—"
        case .monthly: return "Monthly"
        case .yearly:  return "Yearly"
        }
    }
}

// MARK: - SubscriptionStatus

enum SubscriptionStatus: String, Codable {
    case active    = "active"
    case trial     = "trial"
    case cancelled = "cancelled"  // отменена, действует до endDate
    case expired   = "expired"
    case pending   = "pending"    // ожидает подтверждения платежа
}

// MARK: - PaymentRecord
// Firestore: users/{uid}/paymentHistory/{paymentId}

struct PaymentRecord: Codable {
    var id:            String
    var date:          Date
    var amount:        Double
    var currency:      String
    var plan:          String
    var billingCycle:  String
    var paymentMethod: String   // "sbp" | "ru_card" | "foreign_card"
    var status:        String   // PaymentStatus.rawValue
    var failReason:    String?
    var receiptRef:    String?  // Firebase Storage path
}

enum PaymentStatus: String, Codable {
    case success = "success"
    case failed  = "failed"
    case pending = "pending"
}

// MARK: - PlanHistoryRecord
// Firestore: users/{uid}/planHistory/{changeId}

struct PlanHistoryRecord: Codable {
    var id:       String
    var date:     Date
    var fromPlan: String
    var toPlan:   String
    var reason:   String? // "upgrade" | "downgrade" | "trial_start" | "expired"
}

// MARK: - AuthProviderID helper

enum AuthProviderID {
    static func from(_ user: FirebaseAuth.User) -> String {
        if user.isAnonymous { return "anonymous" }
        let providerIDs = user.providerData.map(\.providerID)
        if providerIDs.contains("google.com") { return "google" }
        if providerIDs.contains("apple.com")  { return "apple"  }
        if providerIDs.contains("password")   { return "email"  }
        return "unknown"
    }
}
