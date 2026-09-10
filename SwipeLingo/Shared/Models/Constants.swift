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
        static let appEverLaunched        = "appEverLaunched"        // Bool — fresh install detection, clears stale Keychain token
        static let hasCompletedOnboarding = "hasCompletedOnboarding" // Bool — controls onboarding vs main app flow
        static let userPlan               = "userPlan"               // AccessTier.rawValue — current subscription tier
        static let cachedPlanStatus       = "cachedPlanStatus"       // SubscriptionStatus.rawValue — last known subscription status from Firestore
        static let cachedPlanExpiry       = "cachedPlanExpiry"       // Timубираем Interval — subscription expiry date cached locally
        static let nativeLanguage         = "nativeLanguage"         // NativeLanguage.rawValue — user's native language (ISO 639-1)
        static let colorScheme            = "colorScheme"            // Theme.rawValue — light / dark / system
        static let ttsVoiceIdentifier     = "ttsVoiceIdentifier"     // String — AVSpeechSynthesisVoice identifier, empty = system default
        static let englishVariant         = "englishVariant"         // String — BCP-47 locale for TTS, e.g. "en-US" / "en-GB"
        static let srsEnabled             = "srsEnabled"             // Bool — spaced repetition scheduling on/off
        static let studyStartHour         = "studyStartHour"         // Int — hour of day when SRS "new day" resets (0–23)
        static let studyMode              = "studyMode"              // StudyMode.label — last active tab: Cards or Pairs
        static let pairsAnimationMode     = "pairsAnimationMode"     // AnimationMode.rawValue — manual / auto flip in Pairs
        static let pairsAudioEnabled      = "pairsAudioEnabled"      // Bool — auto-play TTS in Pairs sessions
        static let cachedBillingCycle     = "cachedBillingCycle"     // BillingCycle.rawValue — billing cycle of active subscription
        static let cachedPendingPlan      = "cachedPendingPlan"      // AccessTier.rawValue — plan scheduled after current period ends
        static let cachedPendingCycle     = "cachedPendingCycle"     // BillingCycle.rawValue — cycle of pending plan
    }

    // MARK: - Website

    /// Base URL of the SwipeLingo website. Replace with production URL before release.
    static let websiteBaseURL = "https://swipelingo.app"

    /// Subscription management page — opened when user taps "Subscribe" or "Manage Plan".
    static func subscribeURL(plan: String, cycle: String) -> URL {
        URL(string: "\(websiteBaseURL)/subscribe?plan=\(plan)&cycle=\(cycle)")!
    }

    // MARK: - App Group

    static let appGroupID = "group.PELSH.SwipeLingo"
}
