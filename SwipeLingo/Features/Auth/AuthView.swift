import SwiftUI
import AuthenticationServices

// MARK: - AuthView

struct AuthView: View {

    @Environment(AuthService.self) private var authService

    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String? = nil
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color.myColors.myBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    headerSection

                    Spacer().frame(height: 40)

                    emailPasswordSection

                    Spacer().frame(height: 16)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Color.myColors.myRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                    }

                    primaryButton

                    modeSwitchButton

                    Spacer().frame(height: 28)

                    divider

                    Spacer().frame(height: 24)

                    socialButtons

                    Spacer().frame(height: 32)

                    anonymousButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            Text("SwipeLingo")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.myColors.myAccent)

            Text(mode == .signIn ? "Sign in to continue" : "Create your account")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.mySecondary)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Email / Password

    private var emailPasswordSection: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .textInputStyle()

            SecureField("Password", text: $password)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .textInputStyle()
        }
    }

    // MARK: - Primary Button

    private var primaryButton: some View {
        Button {
            Task { await submitEmailPassword() }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(mode == .signIn ? "Sign In" : "Create Account")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.myColors.myBlue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isLoading || email.isEmpty || password.isEmpty)
        .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1)
        .padding(.bottom, 12)
    }

    private var modeSwitchButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                mode = mode == .signIn ? .signUp : .signIn
                errorMessage = nil
            }
        } label: {
            Text(mode == .signIn
                 ? "Don't have an account? **Sign Up**"
                 : "Already have an account? **Sign In**")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.mySecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Divider

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.15))
            Text("or")
                .font(.footnote)
                .foregroundStyle(Color.myColors.mySecondary)
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.15))
        }
    }

    // MARK: - Social Buttons

    private var socialButtons: some View {
        VStack(spacing: 12) {
            googleSignInButton
            appleSignInButton
        }
    }

    private var googleSignInButton: some View {
        Button {
            Task { await signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                Image("google_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text("Continue with Google")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.myColors.myAccent)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.myColors.myAccent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var appleSignInButton: some View {
        SignInWithAppleButton(
            mode == .signIn ? .signIn : .signUp
        ) { request in
            request.requestedScopes = [.fullName, .email]
            request.nonce = authService.prepareAppleSignIn()
        } onCompletion: { result in
            Task { await handleAppleResult(result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .disabled(isLoading)
    }

    // MARK: - Anonymous

    private var anonymousButton: some View {
        Button {
            Task { await signInAnonymously() }
        } label: {
            Text("Continue as Guest")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
                .underline()
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - Actions

    private func submitEmailPassword() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            if mode == .signIn {
                try await authService.signIn(email: email, password: password)
            } else {
                try await authService.createAccount(email: email, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
            log("[Auth] Email/Password failed: \(error)", level: .error)
        }
    }

    private func signInWithGoogle() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.signInWithGoogle()
        } catch {
            errorMessage = error.localizedDescription
            log("[Auth] Google Sign-In failed: \(error)", level: .error)
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let authorization = try result.get()
            try await authService.signInWithApple(authorization: authorization)
        } catch {
            errorMessage = error.localizedDescription
            log("[Auth] Apple Sign-In failed: \(error)", level: .error)
        }
    }

    private func signInAnonymously() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.signInAnonymously()
        } catch {
            errorMessage = error.localizedDescription
            log("[Auth] Anonymous Sign-In failed: \(error)", level: .error)
        }
    }
}

// MARK: - AuthMode

private enum AuthMode {
    case signIn, signUp
}

// MARK: - TextInput Style

private extension View {
    func textInputStyle() -> some View {
        self
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.myColors.myAccent.opacity(0.2), lineWidth: 1)
            )
            .foregroundStyle(Color.myColors.myAccent)
    }
}
