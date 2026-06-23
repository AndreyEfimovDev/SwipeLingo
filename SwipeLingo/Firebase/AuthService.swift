import Foundation
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import AuthenticationServices
import CryptoKit

// MARK: - AuthService

@Observable
@MainActor
final class AuthService {

    private(set) var currentUser: FirebaseAuth.User? = nil
    private(set) var isLoading = true
    /// True only after the cached session has been confirmed with Firebase (or after a fresh sign-in).
    /// Firebase calls that write data must be guarded by this flag to prevent stale-token writes.
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
                // Keep isLoading = true until session is verified so the UI
                // never renders AppView with an unverified (possibly deleted) user.
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
        // Use provided name or fall back to email prefix
        let resolvedName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(email.prefix(while: { $0 != "@" }))
            : name.trimmingCharacters(in: .whitespaces)
        try await updateDisplayName(resolvedName)
        try? await Auth.auth().currentUser?.sendEmailVerification()
        log("[Auth] Verification email sent to \(email)", level: .info)
    }

    func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await user.sendEmailVerification()
        log("[Auth] Verification email resent to \(user.email ?? "")", level: .info)
    }

    func updateDisplayName(_ name: String) async throws {
        guard let user = Auth.auth().currentUser else { return }
        let req = user.createProfileChangeRequest()
        req.displayName = name.trimmingCharacters(in: .whitespaces)
        try await req.commitChanges()
        currentUser = Auth.auth().currentUser
        log("[Auth] displayName updated to '\(name)'", level: .info)
    }

    /// Sets displayName to the email prefix if it is currently empty.
    private func ensureDisplayName() async {
        guard let user = Auth.auth().currentUser,
              (user.displayName ?? "").isEmpty,
              let email = user.email, !email.isEmpty
        else { return }
        let name = String(email.prefix(while: { $0 != "@" }))
        try? await updateDisplayName(name)
    }

    /// Reloads Firebase user to pick up fresh isEmailVerified status.
    func reloadUser() async {
        guard Auth.auth().currentUser != nil else { return }
        do {
            try await Auth.auth().currentUser?.reload()
            currentUser = Auth.auth().currentUser
        } catch {
            // Transient error (network, token refresh) — keep existing session intact
            log("[AuthService] reloadUser failed, keeping session: \(error.localizedDescription)", level: .warning)
        }
    }

    /// Called once from the auth state listener on initial app launch.
    /// Keeps isLoading = true until Firebase confirms the session is valid.
    /// All user types (including anonymous) are verified — deleted accounts are signed out.
    /// Network errors are ignored so the user can work offline.
    private func verifyAndFinishLoading() async {
        guard isLoading else { return }
        defer { isLoading = false }
        guard let user = Auth.auth().currentUser else { return }
        do {
            // Cap reload() at 8 seconds. Genuine "no internet" (-1009) fails immediately
            // so the timeout only fires when the network exists but the auth server stalls
            // (e.g. a deleted Apple user causing a token-refresh hang of up to 30 s).
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
            // Firebase wraps underlying NSURLErrors as AuthErrorCode.networkError (17020).
            // Inspect the underlying error to distinguish true "no internet" (-1009) from
            // a timeout (-1001): timeout → sign out; no internet → keep session (offline).
            let genuinelyOfflineCodes: Set<Int> = [
                NSURLErrorNotConnectedToInternet,  // -1009
                NSURLErrorNetworkConnectionLost,   // -1005
                NSURLErrorDataNotAllowed,          // -1020
            ]
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            let isOffline = genuinelyOfflineCodes.contains(error.code)
                || (error.code == AuthErrorCode.networkError.rawValue
                    && underlying.map { genuinelyOfflineCodes.contains($0.code) } == true)
            if isOffline {
                log("[Auth] Launch verify: offline — keeping session", level: .warning)
            } else {
                log("[Auth] Launch verify: session invalid (domain:\(error.domain) code:\(error.code) underlying:\(String(describing: underlying?.code))) — signing out", level: .warning)
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
        log("[Auth] Password reset email sent to \(email)", level: .info)
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        // Delete Firestore document first while auth token is still valid.
        // user.delete() removes the Auth record but leaves Firestore data intact.
        try? await Firestore.firestore().collection("users").document(user.uid).delete()
        try await user.delete()
        currentUser = nil
        isSessionVerified = false
        log("[Auth] Account deleted: \(user.uid)", level: .info)
    }

    // App Store Guidelines 5.1.1: Apple requires token revocation when deleting an account.
    // Without this, the Apple ID stays "linked" to the app on Apple's side, and the next
    // Sign in with Apple creates a new Firebase account instead of signing into the old one.
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
        log("[Auth] Apple account deleted + token revoked: \(user.uid)", level: .info)
    }

    // MARK: - Sign Out

    func signOut() throws {
        try Auth.auth().signOut()
        currentUser = nil
        isSessionVerified = false
    }

    // MARK: - Private helpers

    /// If the current user is anonymous, links the credential to preserve the UID.
    /// Otherwise performs a regular sign-in.
    private func signInOrLink(with credential: AuthCredential) async throws -> AuthDataResult {
        if isAnonymous, let user = Auth.auth().currentUser {
            do {
                return try await user.link(with: credential)
            } catch let error as NSError
                where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                log("[Auth] Credential already in use, signing in to existing account", level: .info)
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
