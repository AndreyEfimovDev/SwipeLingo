import Foundation
import SwiftData

// MARK: - AppSyncState
// Singleton SwiftData model synced via CloudKit.
// Stores settings that must be identical across all user devices.
// One record per device, merged on conflict (see AppSyncStateManager).

@Model
final class AppSyncState {
    var id: String = "app_state_singleton"

    // Onboarding
    var hasCompletedOnboarding: Bool = false

    // Study settings
    var srsEnabled: Bool = true
    var studyStartHour: Int = 6

    // Localisation
    var nativeLanguageRaw: String = NativeLanguage.russian.rawValue

    // Conflict resolution: keep the record with the latest settingsUpdatedAt
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
