import Foundation

// MARK: - Constants
// Non-sensitive app-wide constants.
// Sensitive values (API keys, URLs) → Secrets.swift (gitignored)

enum Constants {

    // MARK: - Paywall

    /// Number of paid items (cards or pairs) shown with full content per session
    /// before switching to degraded preview (front-only for cards, left-word-only for pairs).
    static let paywallPreviewLimit = 5

    // MARK: - Subscription

    /// Grace period after subscription expiry before downgrading to Free (in days).
    static let subscriptionGracePeriodDays = 3

    /// Trial duration in days for new Go/Pro subscribers.
    static let trialDurationDays = 7

    /// Days before expiry to send first renewal reminder notification.
    static let notificationReminderDays1 = 7

    /// Days before expiry to send second renewal reminder notification.
    static let notificationReminderDays2 = 1

    // MARK: - Pricing (EUR / USD / RUB)
    // Placeholder — replace with real StoreKit product IDs when billing is integrated.

    enum Price {
        static let goYearlyEUR:  Double = 20
        static let goYearlyUSD:  Double = 20
        static let goYearlyRUB:  Double = 1999

        static let proYearlyEUR: Double = 40
        static let proYearlyUSD: Double = 40
        static let proYearlyRUB: Double = 3999

        // Monthly = yearly / 12 (placeholder until real monthly tiers are defined)
        static let goMonthlyEUR:  Double = goYearlyEUR  / 12
        static let goMonthlyUSD:  Double = goYearlyUSD  / 12
        static let goMonthlyRUB:  Double = goYearlyRUB  / 12

        static let proMonthlyEUR: Double = proYearlyEUR / 12
        static let proMonthlyUSD: Double = proYearlyUSD / 12
        static let proMonthlyRUB: Double = proYearlyRUB / 12

        static let perSetEUR: Double = 1
        static let perSetUSD: Double = 1
        static let perSetRUB: Double = 99
    }

    // MARK: - AppStorage Keys

    enum StorageKey {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let userPlan               = "userPlan"
        static let cachedPlanExpiry       = "cachedPlanExpiry"    // TimeInterval (Date)
        static let cachedPlanStatus       = "cachedPlanStatus"    // SubscriptionStatus.rawValue
        static let nativeLanguage         = "nativeLanguage"
        static let colorScheme            = "colorScheme"
        static let ttsVoiceIdentifier     = "ttsVoiceIdentifier"
        static let srsEnabled             = "srsEnabled"
        static let studyMode              = "studyMode"
    }

    // MARK: - App Group

    static let appGroupID = "group.PELSH.SwipeLingo"
}
