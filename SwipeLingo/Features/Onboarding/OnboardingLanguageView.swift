import SwiftUI

// MARK: - OnboardingLanguageView
// Шаг 1: выбор родного языка пользователя.
// Сохраняет выбор в @AppStorage("nativeLanguage") как ISO-код (NativeLanguage.rawValue).
// Язык выбирается однократно — сменить после онбординга нельзя.

struct OnboardingLanguageView: View {

    var onNext: () -> Void

    @AppStorage("nativeLanguage") private var nativeLanguage: NativeLanguage = .russian

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Text("🌍")
                    .font(.system(size: 56))
                    .padding(.top, 24)

                Text("Choose your language")
                    .font(.title2.bold())
                    .foregroundStyle(Color.myColors.myAccent)

                Text("Select your native language")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            // Language grid
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(NativeLanguage.allCases, id: \.self) { lang in
                    languageCard(lang)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Warning
            HStack(spacing: 6) {
                Image(systemName: "lock")
                    .font(.caption2.weight(.semibold))
                Text("This choice cannot be changed after setup")
                    .font(.caption)
            }
            .foregroundStyle(Color.myColors.myRed.opacity(0.8))
            .padding(.bottom, 12)

            // Continue button
            continueButton
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }

    private func languageCard(_ lang: NativeLanguage) -> some View {
        let isSelected = nativeLanguage == lang
        return Button { nativeLanguage = lang } label: {
            HStack(spacing: 10) {
                Text(lang.flag)
                    .font(.title3)
                Text(lang.displayName)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.myColors.myBlue : Color.myColors.myAccent)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.myColors.myBlue)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).fill(Color.myColors.myBlue.opacity(0.08))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.myColors.myBlue.opacity(0.3) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: isSelected)
    }

    private var continueButton: some View {
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
    }
}
