import Foundation

// MARK: - AppSettings
///
/// Общие пользовательские настройки, читаемые в нескольких экранах сразу —
/// консолидированы в один @Observable объект вместо повторения
/// `@AppStorage(...)` в каждом View. Собирается один раз в composition root
/// (SwipeLingoApp), передаётся вниз через AppDependencies.
///
/// nativeLanguage/srsEnabled/studyStartHour сюда НЕ переносились — для них уже был
/// canonical-сервис AppSyncStateService (SwiftData + CloudKit-синк), консолидация
/// свелась к чтению оттуда напрямую вместо параллельного @AppStorage. AppSettings -
/// для настроек, у которых такого сервиса нет (чисто локальные, без CloudKit-синка).

@Observable
final class AppSettings {
    var theme: Theme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Constants.StorageKey.colorScheme)
        }
    }

    var ttsVoiceIdentifier: String {
        didSet {
            UserDefaults.standard.set(ttsVoiceIdentifier, forKey: Constants.StorageKey.ttsVoiceIdentifier)
        }
    }

    var englishVariant: String {
        didSet {
            UserDefaults.standard.set(englishVariant, forKey: Constants.StorageKey.englishVariant)
        }
    }

    var pairsAnimationMode: AnimationMode {
        didSet {
            UserDefaults.standard.set(pairsAnimationMode.rawValue, forKey: Constants.StorageKey.pairsAnimationMode)
        }
    }

    var pairsAudioEnabled: Bool {
        didSet {
            UserDefaults.standard.set(pairsAudioEnabled, forKey: Constants.StorageKey.pairsAudioEnabled)
        }
    }

    var bookFontSize: Int {
        didSet {
            UserDefaults.standard.set(bookFontSize, forKey: Constants.StorageKey.bookFontSize)
        }
    }

    var appleRelayBannerDismissed: Bool {
        didSet {
            UserDefaults.standard.set(appleRelayBannerDismissed, forKey: Constants.StorageKey.appleRelayBannerDismissed)
        }
    }

    init() {
        let savedTheme = UserDefaults.standard.string(forKey: Constants.StorageKey.colorScheme) ?? ""
        
        theme = Theme(rawValue: savedTheme) ?? .system
        
        ttsVoiceIdentifier = UserDefaults.standard.string(forKey: Constants.StorageKey.ttsVoiceIdentifier) ?? ""
        
        englishVariant = UserDefaults.standard.string(forKey: Constants.StorageKey.englishVariant) ?? "en-US"

        let savedAnimationMode = UserDefaults.standard.string(forKey: Constants.StorageKey.pairsAnimationMode) ?? ""
        
        pairsAnimationMode = AnimationMode(rawValue: savedAnimationMode) ?? .manual
        
        // Значение по умолчанию — object(forKey:), а не bool(forKey:): у отсутствующего
        // ключа bool(forKey:) молча вернул бы false, хотя дефолт должен быть true.
        pairsAudioEnabled = UserDefaults.standard.object(forKey: Constants.StorageKey.pairsAudioEnabled) as? Bool ?? true
        
        let savedFontSize = UserDefaults.standard.object(forKey: Constants.StorageKey.bookFontSize) as? Int

        bookFontSize = savedFontSize ?? 18

        appleRelayBannerDismissed = UserDefaults.standard.bool(forKey: Constants.StorageKey.appleRelayBannerDismissed)
    }
}
