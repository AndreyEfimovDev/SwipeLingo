import SwiftUI
import FirebaseAuth

// MARK: - AdminAuthView
//
// Simple email/password sign-in gate for the Admin tool.
// Shown on launch if no Firebase user is authenticated.

struct AdminAuthView: View {

    @State private var email    = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    let onSignedIn: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.blue.opacity(0.8))

            Text("SwipeLingo Admin")
                .font(.title.weight(.semibold))

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit { signIn() }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .frame(maxWidth: 300)
                    .multilineTextAlignment(.center)
            }

            Button(action: signIn) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Sign In")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(email.isEmpty || password.isEmpty || isLoading)

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 380)
        .onAppear {
            // Always force fresh sign-in to ensure valid token
            try? Auth.auth().signOut()
        }
    }

    private func signIn() {
        isLoading    = true
        errorMessage = nil
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            isLoading = false
            if let error {
                errorMessage = error.localizedDescription
            } else {
                onSignedIn()
            }
        }
    }
}
