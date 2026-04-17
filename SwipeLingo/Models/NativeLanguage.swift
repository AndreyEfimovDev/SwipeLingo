import Foundation

// MARK: - NativeLanguage
//
// Родной язык пользователя — выбирается однократно при онбординге, изменить нельзя.
// Используется как ключ в FSCard.translations и FSCard.sampleTranslations.
//
// Хранится в @AppStorage("nativeLanguage") как rawValue (ISO 639-1 код, например "ru").
// Совместим с @AppStorage: RawRepresentable where RawValue == String.

enum NativeLanguage: String, CaseIterable, Codable {
    case russian    = "ru"
    case chinese    = "zh"
    case spanish    = "es"
    case french     = "fr"
    case arabic     = "ar"
    case portuguese = "pt"
    case german     = "de"
    case japanese   = "ja"
    case korean     = "ko"
    case hindi      = "hi"
    case turkish    = "tr"
    case italian    = "it"
    case indonesian = "id"

    var displayName: String {
        switch self {
        case .russian:    "Русский"
        case .chinese:    "中文"
        case .spanish:    "Español"
        case .french:     "Français"
        case .arabic:     "العربية"
        case .portuguese: "Português"
        case .german:     "Deutsch"
        case .japanese:   "日本語"
        case .korean:     "한국어"
        case .hindi:      "हिन्दी"
        case .turkish:    "Türkçe"
        case .italian:    "Italiano"
        case .indonesian: "Bahasa Indonesia"
        }
    }

    /// ISO 639-1 код языка — используется как ключ в Firestore (translations/sampleTranslations)
    /// и как BCP-47 идентификатор для Apple Translation framework.
    var langId: String {
        switch self {
        case .russian:    "ru"
        case .chinese:    "zh"
        case .spanish:    "es"
        case .french:     "fr"
        case .arabic:     "ar"
        case .portuguese: "pt"
        case .german:     "de"
        case .japanese:   "ja"
        case .korean:     "ko"
        case .hindi:      "hi"
        case .turkish:    "tr"
        case .italian:    "it"
        case .indonesian: "id"
        }
    }

    var flag: String {
        switch self {
        case .russian:    "🇷🇺"
        case .chinese:    "🇨🇳"
        case .spanish:    "🇪🇸"
        case .french:     "🇫🇷"
        case .arabic:     "🇸🇦"
        case .portuguese: "🇧🇷"
        case .german:     "🇩🇪"
        case .japanese:   "🇯🇵"
        case .korean:     "🇰🇷"
        case .hindi:      "🇮🇳"
        case .turkish:    "🇹🇷"
        case .italian:    "🇮🇹"
        case .indonesian: "🇮🇩"
        }
    }
}
