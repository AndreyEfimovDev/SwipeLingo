import Foundation
import SwiftData

// MARK: - AppSyncState
// Singleton-модель SwiftData, синхронизируемая через CloudKit.
// Хранит настройки, которые должны быть одинаковыми на всех устройствах пользователя.
//
// `id` — ключ singleton'а, привязанный к Firebase-аккаунту, не к устройству/iCloud:
// - "app_state_singleton" — device-wide bootstrap-запись, создаётся в AppSyncStateService.init()
//   до того, как известен firebaseUID (Firebase auth-состояние ещё не разрешилось).
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
    var id: String = "app_state_singleton"

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
        self.srsEnabled = srsEnabled
        self.studyStartHour = studyStartHour
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.nativeLanguageRaw = nativeLanguageRaw
        self.settingsUpdatedAt = Date()
    }
}
