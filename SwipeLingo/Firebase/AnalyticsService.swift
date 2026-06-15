import Foundation
import FirebaseAnalytics
import FirebaseCrashlytics

// MARK: - AnalyticsService
//
// Centralised wrapper for Firebase Analytics + Crashlytics.
// Call from anywhere in the app — all event names and param keys are typed.

enum AnalyticsService {

    // MARK: - User identity

    /// Call after successful sign-in so Crashlytics and Analytics link events to a user.
    static func setUser(id: String) {
        Analytics.setUserID(id)
        Crashlytics.crashlytics().setUserID(id)
    }

    static func clearUser() {
        Analytics.setUserID(nil)
        Crashlytics.crashlytics().setUserID("")
    }

    // MARK: - Non-fatal error logging

    static func recordError(_ error: Error, context: String? = nil) {
        var info: [String: Any] = [:]
        if let context { info["context"] = context }
        Crashlytics.crashlytics().record(error: error, userInfo: info)
        log("[Crashlytics] recorded error: \(error) context=\(context ?? "-")", level: .error)
    }

    static func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    // MARK: - Onboarding

    static func onboardingCompleted(nativeLanguage: String, cefrLevel: String) {
        Analytics.logEvent("onboarding_completed", parameters: [
            "native_language": nativeLanguage,
            "cefr_level":      cefrLevel
        ])
    }

    // MARK: - Study sessions (FlashCards)

    static func studySessionStarted(setId: String, setName: String, cardCount: Int) {
        Analytics.logEvent("study_session_started", parameters: [
            "set_id":     setId,
            "set_name":   setName,
            "card_count": cardCount
        ])
    }

    static func studySessionCompleted(setId: String, learntCount: Int, deletedCount: Int, totalCards: Int) {
        Analytics.logEvent("study_session_completed", parameters: [
            "set_id":        setId,
            "learnt_count":  learntCount,
            "deleted_count": deletedCount,
            "total_cards":   totalCards
        ])
    }

    static func cardSwiped(direction: CardSwipeDirection, setId: String) {
        Analytics.logEvent("card_swiped", parameters: [
            "direction": direction.rawValue,
            "set_id":    setId
        ])
    }

    static func wordLookedUp(word: String, source: WordLookupSource) {
        Analytics.logEvent("word_looked_up", parameters: [
            "word":   word,
            "source": source.rawValue
        ])
    }

    static func exampleAddedToCard(word: String) {
        Analytics.logEvent("example_added_to_card", parameters: ["word": word])
    }

    // MARK: - Pairs

    static func pairsSessionStarted(setId: String, cardCount: Int) {
        Analytics.logEvent("pairs_session_started", parameters: [
            "set_id":     setId,
            "card_count": cardCount
        ])
    }

    static func pairsSessionCompleted(setId: String, score: Int, total: Int) {
        Analytics.logEvent("pairs_session_completed", parameters: [
            "set_id": setId,
            "score":  score,
            "total":  total
        ])
    }

    // MARK: - Books

    static func bookOpened(bookId: String, bookTitle: String) {
        Analytics.logEvent("book_opened", parameters: [
            "book_id":    bookId,
            "book_title": bookTitle
        ])
    }

    static func bookChapterRead(bookId: String, chapterIndex: Int, totalChapters: Int) {
        Analytics.logEvent("book_chapter_read", parameters: [
            "book_id":       bookId,
            "chapter_index": chapterIndex,
            "total_chapters": totalChapters
        ])
    }

    static func wordSavedFromBook(word: String, bookId: String) {
        Analytics.logEvent("word_saved_from_book", parameters: [
            "word":    word,
            "book_id": bookId
        ])
    }

    // MARK: - Share Extension / Inbox

    static func wordSavedFromShareExtension(wordCount: Int) {
        Analytics.logEvent("word_saved_from_share_extension", parameters: [
            "word_count": wordCount
        ])
    }

    // MARK: - Monetisation

    static func plansScreenOpened() {
        Analytics.logEvent("plans_screen_opened", parameters: nil)
    }

    static func trialStarted(plan: String) {
        Analytics.logEvent("trial_started", parameters: ["plan": plan])
    }

    static func subscriptionUpgraded(from: String, to: String, cycle: String) {
        Analytics.logEvent("subscription_upgraded", parameters: [
            "from_plan": from,
            "to_plan":   to,
            "cycle":     cycle
        ])
    }

    static func subscriptionCancelled(plan: String) {
        Analytics.logEvent("subscription_cancelled", parameters: ["plan": plan])
    }

    static func paywallShown(setId: String, requiredTier: String) {
        Analytics.logEvent("paywall_shown", parameters: [
            "set_id":        setId,
            "required_tier": requiredTier
        ])
    }
}

// MARK: - Supporting enums

enum CardSwipeDirection: String {
    case right  // learnt / keep
    case left   // skip / later
    case up     // delete
}

enum WordLookupSource: String {
    case tinderCards = "tinder_cards"
    case book        = "book"
}
