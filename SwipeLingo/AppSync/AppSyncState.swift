import Foundation
import SwiftData

// MARK: - AppSyncState
// Singleton-модель SwiftData, синхронизируемая через CloudKit.
// Хранит настройки, которые должны быть одинаковыми на всех устройствах пользователя.
//
// `id` — ключ singleton'а, привязанный к Firebase-аккаунту, не к устройству/iCloud:
<<<<<<< HEAD
// - "app_state_singleton" — device-wide bootstrap-запись, создаётся в AppSyncStateService.init()
//   до того, как известен firebaseUID (Firebase auth-состояние ещё не разрешилось).
=======
// - Constants.appSyncBootstrapID ("app_state_singleton") — device-wide bootstrap-запись,
//   создаётся в AppSyncStateService.init() до того, как известен firebaseUID (Firebase
//   auth-состояние ещё не разрешилось).
>>>>>>> dev
// - "app_state_<firebaseUID>" — запись, закреплённая за конкретным аккаунтом. Переход
//   из bootstrap в этот вид происходит через AppSyncStateManager.claim(firebaseUID:),
//   вызывается один раз после verified-сессии (см. SwipeLingoApp).
// Это защищает от кейса "общий iCloud, разные Firebase-аккаунты" (напр. родитель и
// ребёнок на общем Apple ID, но каждый залогинен в приложении под своим аккаунтом) —
// без этого второй аккаунт мог бы унаследовать hasCompletedOnboarding/настройки первого
// через общий CloudKit private database.
//
// При конфликте (дубли по одному и тому же id) объединяются — см. AppSyncStateManager.

@Model
final class AppSyncState {
    var id: String = Constants.appSyncBootstrapID

    // Онбординг
    var hasCompletedOnboarding: Bool = false

    // Настройки обучения
    var srsEnabled: Bool = true
    var studyStartHour: Int = 6

    // Локализация
    var nativeLanguageRaw: String = NativeLanguage.russian.rawValue

    // Разрешение конфликтов: оставляем запись с самым свежим settingsUpdatedAt
    var settingsUpdatedAt: Date = Date()

    init(
        srsEnabled: Bool = true,
        studyStartHour: Int = 6,
        hasCompletedOnboarding: Bool = false,
        nativeLanguageRaw: String = NativeLanguage.russian.rawValue
    ) {
        // Явно, а не полагаясь на декларативный default выше — на всякий случай,
        // раз уже ловили странности с @Model-свойствами, не тронутыми в init
        // (didSet-баг в UserProfile.swift). Реальную причину malloc-краша,
        // который подозревали здесь изначально, нашли позже — деаллокация
        // MainActor-класса, хранящего ModelContext (см. предупреждение в
        // AppSyncStateManager.swift), эта строка тут просто для симметрии/
        // подстраховки, не подтверждённый фикс чего-либо конкретного.
        self.id = Constants.appSyncBootstrapID
        self.srsEnabled = srsEnabled
        self.studyStartHour = studyStartHour
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.nativeLanguageRaw = nativeLanguageRaw
        self.settingsUpdatedAt = Date()
    }
}
