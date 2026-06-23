import SwiftUI
import AuthenticationServices

// MARK: - AuthView
// Used in two contexts:
//   • Standalone — shown after sign-out (no cancel, no guest option)
//   • Sheet from ProfileView — isDismissible: true (Cancel button, no guest option)
// "Continue as Guest" lives only in OnboardingAuthView.

struct AuthView: View {

    var isDismissible: Bool = false

    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AuthMode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String? = nil
    @State private var isLoading = false
    @State private var showResetConfirm = false
    @State private var showResetSent = false

    private var isEmailValid: Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: true)
        return parts.count == 2 && (parts.last?.contains(".") == true)
    }
    private var canSubmit: Bool { isEmailValid && !password.isEmpty }

    var body: some View {
        ZStack {
            Color.myColors.myBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    headerSection

                    Spacer().frame(height: 24)

                    modePicker

                    Spacer().frame(height: 24)

                    emailPasswordSection

                    if mode == .signIn && isEmailValid {
                        HStack {
                            Spacer()
                            Button("Forgot password?") { showResetConfirm = true }
                                .font(.footnote)
                                .foregroundStyle(Color.myColors.myBlue.opacity(0.8))
                        }
                        .padding(.top, 4)
                    }

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

                    Spacer().frame(height: 28)

                    divider

                    Spacer().frame(height: 24)

                    socialButtons
                }
                .padding(.horizontal, 24)
                .padding(.top, isDismissible ? 24 : 60)
                .padding(.bottom, 40)
            }
        }
        .alert("Reset Password", isPresented: $showResetConfirm) {
            Button("Send Link") { Task { await sendReset() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A password reset link will be sent to \(email).")
        }
        .alert("Email Sent", isPresented: $showResetSent) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Check your inbox and follow the link to reset your password.")
        }
        .if(isDismissible) { view in
            NavigationStack {
                view
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { dismiss() }
                                .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                        }
                    }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Text("SwipeLingo")
            .font(.largeTitle.bold())
            .foregroundStyle(Color.myColors.myAccent)
            .multilineTextAlignment(.center)
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

    // MARK: - Email / Password

    private var emailPasswordSection: some View {
        VStack(spacing: 12) {
            if mode == .signUp {
                TextField("Name (optional)", text: $name)
                    .textContentType(.name)
                    .textInputStyle()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .textInputStyle(invalid: !email.isEmpty && !isEmailValid)
            SecureField("Password", text: $password)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .textInputStyle()
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
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
        .padding(.bottom, 12)
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
            Text("Use the same sign-in method on all devices to keep your progress")
                .font(.caption)
                .foregroundStyle(Color.myColors.mySecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
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

    private func sendReset() async {
        errorMessage = nil
        do {
            try await authService.sendPasswordReset(email: email)
            showResetSent = true
        } catch {
            errorMessage = error.localizedDescription
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
}

// MARK: - AuthMode

private enum AuthMode {
    case signIn, signUp
}

// MARK: - TextInput Style

private extension View {
    func textInputStyle(invalid: Bool = false) -> some View {
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
