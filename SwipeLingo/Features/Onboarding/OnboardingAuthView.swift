import SwiftUI
import AuthenticationServices

// MARK: - OnboardingAuthView
// Step 3 of onboarding — optional sign-in before entering the app.
// Calls onNext() after any successful auth (including anonymous).
// If the user navigated back and is already authenticated, shows a Continue button.

struct OnboardingAuthView: View {

    var onNext: () -> Void

    @Environment(AuthService.self) private var authService

    @State private var mode: AuthMode = .signUp
    @State private var name    = ""
    @State private var email   = ""
    @State private var password = ""
    @State private var errorMessage: String? = nil
    @State private var isLoading = false

    private enum AuthMode { case signIn, signUp }

    private var isEmailValid: Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: true)
        return parts.count == 2 && (parts.last?.contains(".") == true)
    }
    private var canSubmit: Bool { isEmailValid && !password.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                authFormBody
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .onAppear {
            if authService.isAuthenticated { onNext() }
        }
    }

    // MARK: - Auth Form

    private var authFormBody: some View {
        VStack(spacing: 0) {
            header(
                title: mode == .signIn ? "Sign in to continue" : "Create your account",
                subtitle: "Save your progress and unlock premium content"
            )
            .padding(.top, 16)

            Spacer().frame(height: 24)

            modePicker

            Spacer().frame(height: 24)

            VStack(spacing: 12) {
                if mode == .signUp {
                    TextField("Name (optional)", text: $name)
                        .textContentType(.name)
                        .onboardingInputStyle()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .onboardingInputStyle(invalid: !email.isEmpty && !isEmailValid)
                SecureField("Password", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .onboardingInputStyle()
            }
            .animation(.easeInOut(duration: 0.2), value: mode)

            Spacer().frame(height: 16)

            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color.myColors.myRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }

            Button {
                Task { await submitEmailPassword() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView().progressViewStyle(.circular)
                            .tint(canSubmit ? .white : Color.myColors.myAccent)
                    } else {
                        Text(mode == .signIn ? "Sign In" : "Create Account")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(canSubmit ? .white : Color.myColors.myAccent.opacity(0.4))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canSubmit ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isLoading || !canSubmit)
            .padding(.bottom, 28)

            HStack(spacing: 12) {
                Rectangle().frame(height: 1).foregroundStyle(Color.myColors.myAccent.opacity(0.15))
                Text("or").font(.footnote).foregroundStyle(Color.myColors.mySecondary)
                Rectangle().frame(height: 1).foregroundStyle(Color.myColors.myAccent.opacity(0.15))
            }

            Spacer().frame(height: 24)

            VStack(spacing: 12) {
                googleButton
                appleButton
                Text("Use the same sign-in method on all devices to keep your progress")
                    .font(.caption)
                    .foregroundStyle(Color.myColors.mySecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

            Spacer().frame(height: 32)

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
    }

    // MARK: - Header

    private func header(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Color.myColors.myAccent)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.myColors.mySecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 4) {
            modeButton("Sign In", active: mode == .signIn) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    mode = .signIn
                    errorMessage = nil
                    name = ""
                }
            }
            modeButton("Sign Up", active: mode == .signUp) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    mode = .signUp
                    errorMessage = nil
                }
            }
        }
        .padding(4)
        .background(Color.myColors.myAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func modeButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? Color.myColors.myAccent : Color.myColors.mySecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(active ? Color.myColors.myBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .shadow(color: active ? Color.black.opacity(0.06) : Color.clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Social Buttons

    private var googleButton: some View {
        Button {
            Task { await signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                Image("google_logo").resizable().scaledToFit().frame(width: 20, height: 20)
                Text("Continue with Google")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.myColors.myAccent)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.myColors.myAccent.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var appleButton: some View {
        SignInWithAppleButton(mode == .signIn ? .signIn : .signUp) { request in
            request.requestedScopes = [.fullName, .email]
            request.nonce = authService.prepareAppleSignIn()
        } onCompletion: { result in
            Task { await handleApple(result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                try await authService.createAccount(email: email, password: password, name: name)
            }
            onNext()
        } catch {
            errorMessage = error.localizedDescription
            log("[OnboardingAuth] Email/Password failed: \(error)", level: .error)
        }
    }

    private func signInWithGoogle() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.signInWithGoogle()
            onNext()
        } catch {
            errorMessage = error.localizedDescription
            log("[OnboardingAuth] Google failed: \(error)", level: .error)
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let auth = try result.get()
            try await authService.signInWithApple(authorization: auth)
            onNext()
        } catch {
            errorMessage = error.localizedDescription
            log("[OnboardingAuth] Apple failed: \(error)", level: .error)
        }
    }

    private func signInAnonymously() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.signInAnonymously()
            onNext()
        } catch {
            errorMessage = error.localizedDescription
            log("[OnboardingAuth] Anonymous failed: \(error)", level: .error)
        }
    }
}

// MARK: - Input style (scoped to this file)

private extension View {
    func onboardingInputStyle(invalid: Bool = false) -> some View {
        self
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        invalid ? Color.myColors.myRed.opacity(0.6) : Color.myColors.myAccent.opacity(0.2),
                        lineWidth: invalid ? 1.5 : 1
                    )
            )
            .foregroundStyle(Color.myColors.myAccent)
    }
}
