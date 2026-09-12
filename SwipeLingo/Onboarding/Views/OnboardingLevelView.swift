import SwiftUI
import SwiftData

// MARK: - OnboardingLevelView
// Шаг 3: выбор максимального уровня CEFR.
// Сохраняет выбор в UserProfile (SwiftData) — тот же объект используется в ProfileView.

struct OnboardingLevelView: View {

    var onNext: () -> Void
    var onBack: () -> Void

    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context
    @State private var vm = OnboardingLevelViewModel()

    private var profile: UserProfile? { profiles.first }

    // .a1 — тот же дефолт, что и UserProfile(level:) — на первом рендере, до
    // того как .onAppear вставит профиль и @Query его подхватит, подсветка не
    // "мигает" с другого уровня на реальный дефолт.
    private var selectedLevel: CEFRLevel { profile?.cefrLevel ?? .a1 }

    var body: some View {
        VStack(spacing: 0) {
            // Заголовок
            VStack(spacing: 12) {
                Text("📚")
                    .font(.system(size: 56))
                    .padding(.top, 24)

                Text("What's your level?")
                    .font(.title2.bold())
                    .foregroundStyle(Color.myColors.myAccent)

                Text("You'll see content up to your level.\nChange it anytime in your profile.")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // Список уровней
            VStack(spacing: 0) {
                ForEach(Array(CEFRLevel.allCases.enumerated()), id: \.offset) { index, level in
                    if index > 0 {
                        Divider().padding(.leading, 56)
                    }
                    levelRow(level)
                }
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .myShadow()
            .padding(.horizontal, 24)

            Spacer()

            // Продолжить
            Button(action: onNext) {
                Text("Continue")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.myColors.myBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            vm.ensureProfile(profiles: profiles, context: context)
        }
    }

    private func levelRow(_ level: CEFRLevel) -> some View {
        let isSelected = selectedLevel == level
        return Button {
            vm.selectLevel(level, profile: profile)
        } label: {
            HStack(spacing: 14) {
                // Бейдж CEFR
                Text(level.displayCode)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 26)
                    .background(level.color)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(Color.myColors.myAccent)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.myColors.myBlue)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(Rectangle())
            .background(isSelected ? Color.myColors.myBlue.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: isSelected)
    }
}
