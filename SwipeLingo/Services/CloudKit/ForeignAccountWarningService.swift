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
            message: "Looks like you're signed in to different SwipeLingo accounts on your devices. Because of that, we can't sync your progress and settings between them — sign in with the same account on all your devices to keep everything in sync."
        )
    }
}
