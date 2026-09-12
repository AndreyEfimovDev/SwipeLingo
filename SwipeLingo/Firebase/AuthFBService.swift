import Foundation
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import AuthenticationServices
import CryptoKit

// MARK: - AuthService

@Observable
@MainActor
final class AuthFBService {

    private(set) var currentUser: FirebaseAuth.User? = nil
    private(set) var isLoading = true
    /// True только после того, как закэшированная сессия подтверждена Firebase (либо после свежего входа).
    /// Firebase-вызовы, пишущие данные, должны быть защищены этим флагом, чтобы избежать записей по протухшему токену.
    private(set) var isSessionVerified = false

    var isAuthenticated: Bool { currentUser != nil }
    var isAnonymous: Bool { currentUser?.isAnonymous == true }
    var isAppleUser: Bool {
        currentUser?.providerData.contains(where: { $0.providerID == "apple.com" }) == true
    }

    init() {
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                // Держим isLoading = true, пока сессия не подтверждена, чтобы UI
                // никогда не отрисовал AppView с непроверенным (возможно удалённым) пользователем.
                await self?.verifyAndFinishLoading()
            }
        }
    }

    // MARK: - Anonymous

    func signInAnonymously() async throws {
        let result = try await Auth.auth().signInAnonymously()
        isSessionVerified = true
        currentUser = result.user
    }

    // MARK: - Email / Password

    func signIn(email: String, password: String) async throws {
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        let result = try await signInOrLink(with: credential)
        isSessionVerified = true
        currentUser = result.user
    }

    func createAccount(email: String, password: String, name: String = "") async throws {
        do {
            if isAnonymous, let user = Auth.auth().currentUser {
                let credential = EmailAuthProvider.credential(withEmail: email, password: password)
                let result = try await user.link(with: credential)
                currentUser = result.user
            } else {
                let result = try await Auth.auth().createUser(withEmail: email, password: password)
                currentUser = result.user
            }
        } catch let error as NSError
            where error.code == AuthErrorCode.emailAlreadyInUse.rawValue {
            throw AuthError.emailAlreadyInUse
        }
        isSessionVerified = true
        // Используем переданное имя, либо откатываемся на префикс email
        let resolvedName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(email.prefix(while: { $0 != "@" }))
            : name.trimmingCharacters(in: .whitespaces)
        try await updateDisplayName(resolvedName)
        try? await Auth.auth().currentUser?.sendEmailVerification()
        log("Verification email sent to \(email)", level: .info)
    }

    func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await user.sendEmailVerification()
        log("Verification email resent to \(user.email ?? "")", level: .info)
    }

    func updateDisplayName(_ name: String) async throws {
        guard let user = Auth.auth().currentUser else { return }
        let req = user.createProfileChangeRequest()
        req.displayName = name.trimmingCharacters(in: .whitespaces)
        try await req.commitChanges()
        currentUser = Auth.auth().currentUser
        log("displayName updated to '\(name)'", level: .info)
    }

    /// Устанавливает displayName в префикс email, если он сейчас пуст.
    private func ensureDisplayName() async {
        guard let user = Auth.auth().currentUser,
              (user.displayName ?? "").isEmpty,
              let email = user.email, !email.isEmpty
        else { return }
        let name = String(email.prefix(while: { $0 != "@" }))
        try? await updateDisplayName(name)
    }

    /// Перезагружает пользователя Firebase, чтобы получить свежий статус isEmailVerified.
    func reloadUser() async {
        guard Auth.auth().currentUser != nil else { return }
        do {
            try await Auth.auth().currentUser?.reload()
            currentUser = Auth.auth().currentUser
        } catch {
            // Временная ошибка (сеть, обновление токена) — оставляем текущую сессию как есть
            log("reloadUser failed, keeping session: \(error.localizedDescription)", level: .warning)
        }
    }

    /// Вызывается один раз из auth-state листенера при первом запуске приложения.
    /// Держит isLoading = true, пока Firebase не подтвердит валидность сессии.
    /// Проверяются все типы пользователей (включая анонимных) — удалённые аккаунты выходят из системы.
    /// Сетевые ошибки игнорируются, чтобы пользователь мог работать офлайн.
    private func verifyAndFinishLoading() async {
        guard isLoading else { return }
        defer { isLoading = false }
        guard let user = Auth.auth().currentUser else { return }
        do {
            // Ограничиваем reload() 8 секундами. При реальном "нет интернета" (-1009) ошибка
            // приходит сразу, так что таймаут срабатывает только когда сеть есть, но auth-сервер
            // зависает (напр. удалённый Apple-пользователь вызывает зависание обновления токена до 30 с).
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in try await user.reload() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 8_000_000_000)
                    throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
                }
                _ = try await group.next()
                group.cancelAll()
            }
            isSessionVerified = true
            currentUser = Auth.auth().currentUser
        } catch let error as NSError {
            // Firebase оборачивает исходные NSURLError в AuthErrorCode.networkError (17020).
            // Любая сетевая ошибка/таймаут → сохраняем сессию (повтор при следующем запуске).
            // Выход из системы — только по явным auth-ошибкам (невалидный credential, пользователь отключён и т.д.).
            let keepSessionCodes: Set<Int> = [
                NSURLErrorNotConnectedToInternet,  // -1009 нет интернета
                NSURLErrorNetworkConnectionLost,   // -1005 соединение прервано
                NSURLErrorDataNotAllowed,          // -1020 заблокировано в сотовой сети
                NSURLErrorTimedOut,                // -1001 сервер медленный / прокси / VPN
                NSURLErrorCannotConnectToHost,     // -1004 хост недоступен
            ]
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            let isNetworkError = keepSessionCodes.contains(error.code)
                || (error.code == AuthErrorCode.networkError.rawValue
                    && underlying.map { keepSessionCodes.contains($0.code) } == true)
            if isNetworkError {
                log("Launch verify: network error (\(error.code)) — keeping session", level: .warning)
            } else {
                log("Launch verify: session invalid (domain:\(error.domain) code:\(error.code) underlying:\(String(describing: underlying?.code))) — signing out", level: .warning)
                try? signOut()
                currentUser = nil
            }
        }
    }

    // MARK: - Google

    func signInWithGoogle() async throws {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first
        else { throw AuthError.noRootViewController }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingGoogleToken
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        let authResult = try await signInOrLink(with: credential)
        isSessionVerified = true
        currentUser = authResult.user
        await ensureDisplayName()
    }

    // MARK: - Apple

    private var currentNonce: String?

    func prepareAppleSignIn() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    func signInWithApple(authorization: ASAuthorization) async throws {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityTokenData = credential.identityToken,
            let identityToken = String(data: identityTokenData, encoding: .utf8),
            let nonce = currentNonce
        else { throw AuthError.invalidAppleCredential }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: identityToken,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        let result = try await signInOrLink(with: firebaseCredential)
        isSessionVerified = true
        currentUser = result.user
        await ensureDisplayName()
    }

    // MARK: - Password Reset

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
        log("Password reset email sent to \(email)", level: .info)
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        // Сначала удаляем документ Firestore, пока auth-токен ещё валиден.
        // user.delete() удаляет запись Auth, но оставляет данные Firestore нетронутыми.
        try? await Firestore.firestore().collection("users").document(user.uid).delete()
        try await user.delete()
        currentUser = nil
        isSessionVerified = false
        log("Account deleted: \(user.uid)", level: .info)
    }

    // App Store Guidelines 5.1.1: Apple требует отзыва токена при удалении аккаунта.
    // Без этого Apple ID остаётся "привязанным" к приложению на стороне Apple, и следующий
    // Sign in with Apple создаст новый Firebase-аккаунт вместо входа в старый.
    func deleteAccountWithApple(authorization: ASAuthorization) async throws {
        guard let user = Auth.auth().currentUser else { return }
        guard
            let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let authCodeData = appleCredential.authorizationCode,
            let authCode = String(data: authCodeData, encoding: .utf8)
        else { throw AuthError.invalidAppleCredential }

        try await Auth.auth().revokeToken(withAuthorizationCode: authCode)
        try? await Firestore.firestore().collection("users").document(user.uid).delete()
        try await user.delete()
        currentUser = nil
        isSessionVerified = false
        log("Apple account deleted + token revoked: \(user.uid)", level: .info)
    }

    // MARK: - Sign Out

    func signOut() throws {
        try Auth.auth().signOut()
        currentUser = nil
        isSessionVerified = false
    }

    // MARK: - Private helpers

    /// Если текущий пользователь анонимный, привязывает credential, сохраняя UID.
    /// Иначе выполняет обычный вход.
    private func signInOrLink(with credential: AuthCredential) async throws -> AuthDataResult {
        if isAnonymous, let user = Auth.auth().currentUser {
            do {
                return try await user.link(with: credential)
            } catch let error as NSError
                where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                log("Credential already in use, signing in to existing account", level: .info)
                return try await Auth.auth().signIn(with: credential)
            }
        }
        do {
            return try await Auth.auth().signIn(with: credential)
        } catch let error as NSError
            where error.code == AuthErrorCode.accountExistsWithDifferentCredential.rawValue {
            throw AuthError.accountExistsWithDifferentCredential
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess { fatalError("SecRandomCopyBytes failed: \(errorCode)") }
                return random
            }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - AuthError

enum AuthError: LocalizedError {
    case noRootViewController
    case missingGoogleToken
    case invalidAppleCredential
    case accountExistsWithDifferentCredential
    case emailAlreadyInUse

    var errorDescription: String? {
        switch self {
        case .noRootViewController:
            return "Could not find root view controller."
        case .missingGoogleToken:
            return "Google Sign-In did not return an ID token."
        case .invalidAppleCredential:
            return "Apple Sign-In credential is invalid."
        case .accountExistsWithDifferentCredential:
            return "An account with this email already exists. Please sign in with email and password."
        case .emailAlreadyInUse:
            return "This email is already registered. If you signed up with Apple or Google, use those buttons below."
        }
    }
}
