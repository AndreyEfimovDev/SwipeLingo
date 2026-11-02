import Foundation
import FirebaseAuth

// MARK: - FreshInstallGuard
//
// Определяет чистую установку (в т.ч. переустановку) и сбрасывает устаревший
// Firebase Auth токен, переживший переустановку в Keychain. Вынесен из
// SwipeLingoApp — это auth/persistence-bootstrap забота, а не composition-root.

enum FreshInstallGuard {

    /// При самом первом запуске (свежая установка или переустановка) выходит
    /// из закэшированной Firebase Auth сессии — UserDefaults чистится при
    /// переустановке, Keychain — нет, так что без этого пользователь
    /// автоматически авторизуется устаревшим токеном и минует онбординг/экран входа.
    static func clearStaleSessionIfNeeded() {
        // Определение чистой установки: при переустановке UserDefaults очищается, а Keychain — нет.
        // Если это самый первый запуск, удаляем устаревший токен из Keychain,
        // чтобы пользователь заново прошел онбординг и аутентификацию.
        let launchedBefore = UserDefaults.standard.bool(forKey: Constants.StorageKey.appEverLaunched)
        if !launchedBefore {
            try? Auth.auth().signOut()
            UserDefaults.standard.set(true, forKey: Constants.StorageKey.appEverLaunched)
            log("Fresh install detected — Keychain token cleared", level: .info)
        }
    }
}
