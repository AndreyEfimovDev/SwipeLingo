import SwiftUI
import SwiftData

// MARK: - OnboardingNameView
// Шаг 2: ввод имени пользователя.
// Skip → name остаётся пустым, displayName вернёт "Anonymous".
// Сохраняет в UserProfile.name (SwiftData).

struct OnboardingNameView: View {

    var onNext: () -> Void
    var onBack: () -> Void

    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context

    @State private var nameInput: String = ""
    @FocusState private var isFocused: Bool

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Text("👋")
                    .font(.system(size: 56))
                    .padding(.top, 24)

                Text("What's your name?")
                    .font(.title2.bold())
                    .foregroundStyle(Color.myColors.myAccent)

                Text("We'll use it to personalize your experience")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)

            // Name field
            VStack(spacing: 8) {
                TextField("Enter your name", text: $nameInput)
                    .font(.body)
                    .foregroundStyle(Color.myColors.myAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.myColors.myAccent.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isFocused
                                            ? Color.myColors.myBlue.opacity(0.5)
                                            : Color.clear,
                                            lineWidth: 1.5)
                            )
                    )
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit { saveName(); onNext() }

                Text("You can change this later in your profile")
                    .font(.caption)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
            }
            .padding(.horizontal, 24)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button(action: { saveName(); onNext() }) {
                    Text("Continue")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.myColors.myBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button(action: { clearName(); onNext() }) {
                    Text("Skip")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            ensureProfile()
            nameInput = profile?.name ?? ""
            isFocused = true
        }
    }

    // MARK: - Helpers

    private func ensureProfile() {
        if profiles.isEmpty { context.insert(UserProfile()) }
    }

    private func saveName() {
        isFocused = false
        ensureProfile()
        profile?.name = nameInput.trimmingCharacters(in: .whitespaces)
        context.saveWithErrorHandling()
    }

    private func clearName() {
        isFocused = false
        ensureProfile()
        profile?.name = ""
        context.saveWithErrorHandling()
    }
}
