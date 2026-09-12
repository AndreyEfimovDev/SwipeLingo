import Foundation
import FirebaseAuth

/// Узкий протокол над `Auth.auth()` — зеркалит только те методы Firebase Auth,
/// которые реально вызывает `AuthFBService`. Существует ради тестируемости:
/// `AuthFBService` получает эту зависимость через `init`, а не обращается
/// к `Auth.auth()` напрямую, так что в unit-тестах можно подставить fake-реализацию.
///
/// Реальный `Auth` соответствует протоколу "бесплатно" через `extension Auth: AuthClient`
/// ниже — его собственные методы уже имеют нужные сигнатуры, кроме
/// `addStateDidChangeListener`, для которого нужна тонкая склейка (см. extension).
protocol AuthClient {
    var currentUser: FirebaseAuth.User? { get }
    func addStateDidChangeListener(_ listener: @escaping (FirebaseAuth.User?) -> Void)
    func signInAnonymously() async throws -> AuthDataResult
    func createUser(withEmail email: String, password: String) async throws -> AuthDataResult
    func signIn(with credential: AuthCredential) async throws -> AuthDataResult
    func revokeToken(withAuthorizationCode authorizationCode: String) async throws
    func signOut() throws
    func sendPasswordReset(withEmail email: String, actionCodeSettings: ActionCodeSettings?) async throws
}

extension AuthClient {
    /// Удобный оверлоад без `actionCodeSettings` — протокол не поддерживает
    /// значения по умолчанию в requirements, поэтому подставляем `nil` здесь.
    func sendPasswordReset(withEmail email: String) async throws {
        try await sendPasswordReset(withEmail: email, actionCodeSettings: nil)
    }
}

extension Auth: AuthClient {
    /// Обёртка над `Auth.addStateDidChangeListener(_:)`: у настоящего метода первым
    /// параметром коллбэка идёт сам `Auth` — в протоколе он не нужен (вызывающая
    /// сторона и так уже держит свой `AuthClient`), поэтому просто отбрасываем его.
    func addStateDidChangeListener(_ listener: @escaping (FirebaseAuth.User?) -> Void) {
        _ = addStateDidChangeListener { _, user in listener(user) }
    }
}
