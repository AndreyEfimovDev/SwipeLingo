import SwiftUI
import SwiftData

// MARK: - OnboardingWelcomeView
// Шаг 4: приветственный экран.
// Читает имя и уровень из UserProfile.
// onComplete() → SwipeLingoApp устанавливает hasCompletedOnboarding = true.

struct OnboardingWelcomeView: View {

    var onComplete: () -> Void

    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context

    private var profile: UserProfile? { profiles.first }
    private var displayName: String { profile?.displayName ?? "Anonymous" }
    private var cefrLevel: CEFRLevel  { profile?.cefrLevel  ?? .a1 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("🎉")
                .font(.system(size: 72))

            Spacer().frame(height: 32)

            VStack(spacing: 12) {
                Text("Welcome, \(displayName)!")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.myColors.myAccent)
                    .multilineTextAlignment(.center)

                Text("You're all set to start learning English")
                    .font(.body)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 32)

            // Level badge
            HStack(spacing: 10) {
                Text(cefrLevel.displayCode)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 26)
                    .background(cefrLevel.color)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(cefrLevel.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.75))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button(action: onComplete) {
                HStack(spacing: 8) {
                    Text("Get Started")
                        .font(.body.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.myColors.myBlue)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}
