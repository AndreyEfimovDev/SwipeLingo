import Foundation

// MARK: - Constants
// Несекретные константы уровня всего приложения.
// Секретные значения (API-ключи, URL) → Secrets.swift (в .gitignore)

enum Constants {

    // MARK: - Paywall

    /// Количество платных элементов (карточек или пар), показываемых с полным контентом за сессию,
    /// прежде чем переключиться на урезанный превью-режим (только лицо у карточек, только левое слово у пар).
    static let paywallPreviewLimit = 5

    // MARK: - Subscription

    /// Grace period после истечения подписки перед понижением до Free (в днях).
    static let subscriptionGracePeriodDays = 3

    /// Длительность триала в днях для новых подписчиков Go/Pro.
    static let trialDurationDays = 30

    /// Дней до истечения для отправки первого напоминания о продлении.
    static let notificationReminderDays1 = 7

    /// Дней до истечения для отправки второго напоминания о продлении.
    static let notificationReminderDays2 = 1

    // MARK: - Цены (EUR / USD / RUB)
    // Заглушка — заменить на реальные StoreKit product ID, когда будет подключён биллинг.

    enum Price {
        static let goYearlyEUR:  Double = 20
        static let goYearlyUSD:  Double = 20
        static let goYearlyRUB:  Double = 1999

        static let proYearlyEUR: Double = 40
        static let proYearlyUSD: Double = 40
        static let proYearlyRUB: Double = 3999

        // Monthly = yearly / 12 (заглушка, пока не определены реальные месячные тарифы)
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
        static let appEverLaunched        = "appEverLaunched"        // Bool — определение чистой установки, чистит устаревший токен Keychain
        static let hasCompletedOnboarding = "hasCompletedOnboarding" // Bool — управляет онбордингом vs основным флоу приложения
        static let userPlan               = "userPlan"               // AccessTier.rawValue — текущий план подписки
        static let cachedPlanStatus       = "cachedPlanStatus"       // SubscriptionStatus.rawValue — последний известный статус подписки из Firestore
        static let cachedPlanExpiry       = "cachedPlanExpiry"       // TimeInterval — дата истечения подписки, закэширована локально
        static let nativeLanguage         = "nativeLanguage"         // NativeLanguage.rawValue — родной язык пользователя (ISO 639-1)
        static let colorScheme            = "colorScheme"            // Theme.rawValue — light / dark / system
        static let ttsVoiceIdentifier     = "ttsVoiceIdentifier"     // String — идентификатор AVSpeechSynthesisVoice, пусто = системный по умолчанию
        static let englishVariant         = "englishVariant"         // String — BCP-47 локаль для TTS, напр. "en-US" / "en-GB"
        static let srsEnabled             = "srsEnabled"             // Bool — интервальное повторение включено/выключено
        static let studyStartHour         = "studyStartHour"         // Int — час суток, когда сбрасывается "новый день" SRS (0–23)
        static let studyMode              = "studyMode"              // StudyMode.label — последний активный таб: Cards или Pairs
        static let pairsAnimationMode     = "pairsAnimationMode"     // AnimationMode.rawValue — ручной / авто переход в Pairs
        static let pairsAudioEnabled      = "pairsAudioEnabled"      // Bool — автовоспроизведение TTS в сессиях Pairs
        static let cachedBillingCycle     = "cachedBillingCycle"     // BillingCycle.rawValue — цикл оплаты активной подписки
        static let cachedPendingPlan      = "cachedPendingPlan"      // AccessTier.rawValue — план, запланированный после окончания текущего периода
        static let cachedPendingCycle     = "cachedPendingCycle"     // BillingCycle.rawValue — цикл ожидающего плана
        static let pendingInboxWords      = "pendingInboxWords"      // [String] — слова в очереди от Share Extension, читаются через App Group UserDefaults (не @AppStorage — общий между SwipeLingo и SwipeLingoShare)
    }

    // MARK: - Сайт

    /// Базовый URL сайта SwipeLingo. Заменить на продакшен-URL перед релизом.
    static let websiteBaseURL = "https://swipelingo.app"

    /// Страница управления подпиской — открывается, когда пользователь тапает "Subscribe" или "Manage Plan".
    static func subscribeURL(plan: String, cycle: String) -> URL {
        URL(string: "\(websiteBaseURL)/subscribe?plan=\(plan)&cycle=\(cycle)")!
    }

    // MARK: - App Group

    static let appGroupID = "group.PELSH.SwipeLingo"
}
