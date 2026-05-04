import Foundation

// MARK: - NativeLanguage
//
// Родной язык пользователя — выбирается однократно при онбординге, изменить нельзя.
// Используется как ключ в FSCard.translations и FSCard.sampleTranslations.
//
// Хранится в @AppStorage("nativeLanguage") как rawValue (ISO 639-1 код, например "ru").
// Совместим с @AppStorage: RawRepresentable where RawValue == String.

enum NativeLanguage: String, CaseIterable, Codable {
    case russian          = "ru"
    case chinese          = "zh"
    case chineseTraditional = "zh-TW"
    case spanish          = "es"
    case french           = "fr"
    case arabic           = "ar"
    case portuguese       = "pt"
    case german           = "de"
    case dutch            = "nl"
    case japanese         = "ja"
    case korean           = "ko"
    case hindi            = "hi"
    case turkish          = "tr"
    case italian          = "it"
    case polish           = "pl"
    case indonesian       = "id"
    case vietnamese       = "vi"

    var displayName: String {
        switch self {
        case .russian:            "Русский"
        case .chinese:            "中文（简体）"
        case .chineseTraditional: "繁體中文"
        case .spanish:            "Español"
        case .french:             "Français"
        case .arabic:             "العربية"
        case .portuguese:         "Português"
        case .german:             "Deutsch"
        case .dutch:              "Nederlands"
        case .japanese:           "日本語"
        case .korean:             "한국어"
        case .hindi:              "हिन्दी"
        case .turkish:            "Türkçe"
        case .italian:            "Italiano"
        case .polish:             "Polski"
        case .indonesian:         "Bahasa Indonesia"
        case .vietnamese:         "Tiếng Việt"
        }
    }

    /// BCP-47 идентификатор языка — используется как ключ в Firestore (translations/sampleTranslations).
    /// Не менять без миграции Firestore-данных.
    var langId: String {
        switch self {
        case .russian:            "ru"
        case .chinese:            "zh"
        case .chineseTraditional: "zh-TW"
        case .spanish:            "es"
        case .french:             "fr"
        case .arabic:             "ar"
        case .portuguese:         "pt"
        case .german:             "de"
        case .dutch:              "nl"
        case .japanese:           "ja"
        case .korean:             "ko"
        case .hindi:              "hi"
        case .turkish:            "tr"
        case .italian:            "it"
        case .polish:             "pl"
        case .indonesian:         "id"
        case .vietnamese:         "vi"
        }
    }

    /// Locale identifier для Apple Translation framework.
    var translationLocaleId: String { langId }

    var flag: String {
        switch self {
        case .russian:            "🇷🇺"
        case .chinese:            "🇨🇳"
        case .chineseTraditional: "🇹🇼"
        case .spanish:            "🇪🇸"
        case .french:             "🇫🇷"
        case .arabic:             "🇸🇦"
        case .portuguese:         "🇧🇷"
        case .german:             "🇩🇪"
        case .dutch:              "🇳🇱"
        case .japanese:           "🇯🇵"
        case .korean:             "🇰🇷"
        case .hindi:              "🇮🇳"
        case .turkish:            "🇹🇷"
        case .italian:            "🇮🇹"
        case .polish:             "🇵🇱"
        case .indonesian:         "🇮🇩"
        case .vietnamese:         "🇻🇳"
        }
    }
}
