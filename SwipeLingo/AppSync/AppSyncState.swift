import Foundation
import SwiftData

// MARK: - AppSyncState
// Singleton-модель SwiftData, синхронизируемая через CloudKit.
// Хранит настройки, которые должны быть одинаковыми на всех устройствах пользователя.
// Одна запись на устройство, при конфликте объединяются (см. AppSyncStateManager).

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
