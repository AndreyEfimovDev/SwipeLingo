import SwiftUI

// MARK: - OnboardingLanguageView
// Шаг 1: выбор родного языка пользователя.
// Сохраняет выбор в @AppStorage("nativeLanguage") — тот же ключ используется
// в SettingsView, AddEditCardView и DictionaryLookupView.

struct OnboardingLanguageView: View {

    var onNext: () -> Void

    @AppStorage("nativeLanguage") private var nativeLanguage = "Русский"

    private let languages: [(name: String, flag: String)] = [
        ("Русский",   "🇷🇺"),
        ("中文",       "🇨🇳"),
        ("Español",   "🇪🇸"),
        ("Français",  "🇫🇷"),
        ("العربية",   "🇸🇦"),
        ("Português", "🇧🇷"),
        ("Deutsch",   "🇩🇪"),
        ("日本語",     "🇯🇵"),
    ]

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
                ForEach(languages, id: \.name) { lang in
                    languageCard(lang)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Continue button
            continueButton
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }

    private func languageCard(_ lang: (name: String, flag: String)) -> some View {
        let isSelected = nativeLanguage == lang.name
        return Button { nativeLanguage = lang.name } label: {
            HStack(spacing: 10) {
                Text(lang.flag)
                    .font(.title3)
                Text(lang.name)
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
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected
                          ? Color.myColors.myBlue.opacity(0.08)
                          : Color.myColors.myAccent.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.myColors.myBlue.opacity(0.3) : Color.clear,
                                    lineWidth: 1.5)
                    )
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
