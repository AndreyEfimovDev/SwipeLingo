import Foundation
import FirebaseAuth
import GoogleSignIn
import AuthenticationServices
import CryptoKit

// MARK: - AuthService

@Observable
@MainActor
final class AuthService {

    private(set) var currentUser: FirebaseAuth.User? = nil
    private(set) var isLoading = true

    var isAuthenticated: Bool { currentUser != nil }
    var isAnonymous: Bool { currentUser?.isAnonymous == true }

    init() {
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isLoading = false
            }
        }
    }

    // MARK: - Anonymous

    func signInAnonymously() async throws {
        let result = try await Auth.auth().signInAnonymously()
        currentUser = result.user
    }

    // MARK: - Email / Password

    func signIn(email: String, password: String) async throws {
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        let result = try await signInOrLink(with: credential)
        currentUser = result.user
    }

    func createAccount(email: String, password: String) async throws {
        if isAnonymous, let user = Auth.auth().currentUser {
            // Link anonymous account → keeps the same UID
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            let result = try await user.link(with: credential)
            currentUser = result.user
        } else {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            currentUser = result.user
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
        currentUser = authResult.user
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
        currentUser = result.user
    }

    // MARK: - Sign Out

    func signOut() throws {
        try Auth.auth().signOut()
        currentUser = nil
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
                // Credential belongs to an existing account — sign in normally instead
                log("[Auth] Credential already in use, signing in to existing account", level: .info)
                return try await Auth.auth().signIn(with: credential)
            }
        }
        return try await Auth.auth().signIn(with: credential)
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

    var errorDescription: String? {
        switch self {
        case .noRootViewController:   return "Could not find root view controller."
        case .missingGoogleToken:     return "Google Sign-In did not return an ID token."
        case .invalidAppleCredential: return "Apple Sign-In credential is invalid."
        }
    }
}
