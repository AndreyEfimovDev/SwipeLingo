import SwiftUI

// MARK: - OnboardingIntroView
// Шаг 0: приветственный экран.
// Знакомит пользователя с приложением до начала настройки.

struct OnboardingIntroView: View {

    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo / illustration
            VStack(spacing: 20) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.myColors.myBlue)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 10) {
                    Text("Welcome to SwipeLingo")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.myColors.myAccent)
                        .multilineTextAlignment(.center)

                    Text("Learn new English words through\nflashcards and interactive pairs.\nStudy at your own pace, track progress\nwith spaced repetition.")
                        .font(.body)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Feature highlights
            VStack(spacing: 16) {
                featureRow(icon: "rectangle.stack",
                           color: Color.myColors.myBlue,
                           text: "Flashcards with spaced repetition")
                featureRow(icon: "sparkles",
                           color: Color.myColors.myPurple,
                           text: "Pairs — compare word levels")
                featureRow(icon: "chart.line.uptrend.xyaxis",
                           color: Color.myColors.myGreen,
                           text: "Track your learning progress")
            }
            .padding(.horizontal, 32)

            Spacer()

            // Setup hint
            Text("Before we start, let's set up your profile.\nIt will only take a minute.")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

            // CTA
            Button(action: onNext) {
                HStack(spacing: 8) {
                    Text("Let's go")
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

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 32)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.75))
            Spacer()
        }
    }
}
