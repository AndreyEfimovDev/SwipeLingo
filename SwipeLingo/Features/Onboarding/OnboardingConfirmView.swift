import SwiftUI
import SwiftData

// MARK: - OnboardingConfirmView
// Финальный шаг онбординга — сводка настроек и подтверждение.
// Показывает язык, имя, уровень. Пользователь либо подтверждает (→ в приложение)
// либо возвращается к редактированию.

struct OnboardingConfirmView: View {

    var onComplete: () -> Void
    var onBack: () -> Void

    @AppStorage("nativeLanguage") private var nativeLanguage: NativeLanguage = .russian

    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }
    private var displayName: String { profile?.displayName ?? "Anonymous" }
    private var cefrLevel: CEFRLevel { profile?.cefrLevel ?? .a1 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header
            VStack(spacing: 12) {
                Text("✅")
                    .font(.system(size: 64))

                Text("Ready to start?")
                    .font(.title2.bold())
                    .foregroundStyle(Color.myColors.myAccent)

                Text("Please confirm your settings")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.55))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

            Spacer().frame(height: 40)

            // Settings summary
            VStack(spacing: 0) {
                settingRow(
                    icon: nativeLanguage.flag,
                    title: "Native language",
                    value: nativeLanguage.displayName,
                    isLast: false
                )
                settingRow(
                    icon: "👤",
                    title: "Name",
                    value: displayName,
                    isLast: false
                )
                settingRow(
                    icon: "📊",
                    title: "English level",
                    value: "\(cefrLevel.displayCode) — \(cefrLevel.displayName)",
                    isLast: true
                )
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            // Language lock warning
            HStack(spacing: 5) {
                Image(systemName: "lock")
                    .font(.caption2.weight(.semibold))
                Text("Native language cannot be changed after your confirmation")
                    .font(.caption)
            }
            .foregroundStyle(Color.myColors.myRed.opacity(0.8))
            .padding(.top, 12)
            .padding(.horizontal, 32)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button(action: onComplete) {
                    Text("Start Learning")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.myColors.myBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button(action: onBack) {
                    Text("Edit Settings")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private func settingRow(icon: String, title: String, value: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.title3)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
                    Text(value)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.myColors.myAccent)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !isLast {
                Divider()
                    .padding(.leading, 60)
            }
        }
    }
}
