import Foundation

// MARK: - ForeignAccountWarningService
//
// Одноразовое (на устройство) предупреждение, если локально обнаружены данные
// (AppSyncState/UserProfile) ДРУГОГО Firebase-аккаунта на этом же iCloud — см.
// AppSyncStateManager.claim(firebaseUID:) и UserProfileDedupeService.hasForeignProfiles.
// Синк между разными аккаунтами технически невозможен (каждый аккаунт хранит свои
// записи изолированно) — здесь только сообщаем пользователю причину простыми словами.

enum ForeignAccountWarningService {

    /// Показывает блокирующий алерт через `ErrorManager`, если обнаружены чужие
    /// данные (`hasForeignData`) и предупреждение ещё не показывалось на этом
    /// устройстве. Дальнейшие вызовы с `hasForeignData: true` — no-op.
    static func warnIfNeeded(hasForeignData: Bool) {
        let key = Constants.StorageKey.foreignAccountWarningShown
        guard hasForeignData, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        ErrorManager.shared.notify(
            title: "Sync Unavailable",
            // Текст подходит к обоим сценариям: разные аккаунты на разных устройствах одного iCloud
            // и смена аккаунта на этом же устройстве (данные прошлого аккаунта остались локально).
            message: "This iCloud account already has SwipeLingo data from another account. Progress and settings are kept separately for each account and won't sync between them — use the same account on all your devices to keep everything in sync."
        )
    }
}
