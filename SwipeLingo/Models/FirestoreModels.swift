import Foundation

// MARK: - FirestoreModels
//
// Codable-структуры для слоя Firestore. Используются в двух местах:
//   1. SwipeLingoAdmin — создание/редактирование/публикация контента
//   2. FirestoreImportService (основное приложение) — загрузка и конвертация в SwiftData-модели
//
// Все enum-поля хранятся напрямую (Codable сериализует через rawValue автоматически).

// MARK: - SetDeployStatus

enum SetDeployStatus: String, Codable, CaseIterable {
    case new        // создан локально, в Firebase нет
    case ready      // помечен к деплою
    case live       // синхронизирован с Firebase
    case outdated   // был Live, внесены локальные изменения

    var label: String {
        switch self {
        case .new:      "New"
        case .ready:    "Ready"
        case .live:     "Live"
        case .outdated: "Outdated"
        }
    }
}

// MARK: - FSCollection

struct FSCollection: Codable, Identifiable, Hashable {
    var id:        String
    var name:      String
    var icon:      String?         // SF Symbol name or emoji
    var type:      CollectionType
    var isSynced:  Bool            // false = New (локальная), true = из/в Firebase
    var updatedAt: Date
    var createdAt: Date

    init(id: String, name: String, icon: String? = nil, type: CollectionType,
         isSynced: Bool = false, updatedAt: Date, createdAt: Date) {
        self.id        = id
        self.name      = name
        self.icon      = icon
        self.type      = type
        self.isSynced  = isSynced
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}

// MARK: - FSCardSet

struct FSCardSet: Codable, Identifiable, Hashable {
    var id:           String
    var collectionId: String
    var name:         String
    var description:  String?        // optional set description shown in library
    var cefrLevel:    CEFRLevel
    var accessTier:   AccessTier
    var deployStatus: SetDeployStatus
    var updatedAt:    Date
    var createdAt:    Date

    init(id: String, collectionId: String, name: String,
         description: String? = nil,
         cefrLevel: CEFRLevel, accessTier: AccessTier,
         deployStatus: SetDeployStatus = .new,
         updatedAt: Date, createdAt: Date) {
        self.id           = id
        self.collectionId = collectionId
        self.name         = name
        self.description  = description
        self.cefrLevel    = cefrLevel
        self.accessTier   = accessTier
        self.deployStatus = deployStatus
        self.updatedAt    = updatedAt
        self.createdAt    = createdAt
    }
}

// MARK: - FSCard

struct FSCard: Codable, Identifiable, Hashable {
    var id:                 String
    var setId:              String
    var en:                 String
    var transcription:      String
    var translations:       [String: String]         // ["ru": "мать", ...]
    var sampleEN:           [String]
    var sampleTranslations: [String: [String]]       // ["ru": ["пример1"], ...]
    var tag:                String
    var updatedAt:          Date
    var createdAt:          Date

    init(id: String, setId: String, en: String, transcription: String,
         translations: [String: String], sampleEN: [String],
         sampleTranslations: [String: [String]], tag: String,
         updatedAt: Date, createdAt: Date) {
        self.id                 = id
        self.setId              = setId
        self.en                 = en
        self.transcription      = transcription
        self.translations       = translations
        self.sampleEN           = sampleEN
        self.sampleTranslations = sampleTranslations
        self.tag                = tag
        self.updatedAt          = updatedAt
        self.createdAt          = createdAt
    }

    func translation(for language: NativeLanguage) -> String {
        translations[language.langId] ?? ""
    }

    func sampleTranslation(for language: NativeLanguage) -> [String] {
        sampleTranslations[language.langId] ?? []
    }
}

// MARK: - FSPairsSet

struct FSPairsSet: Codable, Identifiable {
    var id:           String
    var collectionId: String
    var title:        String?
    var subtitle:     String?
    var description:  String?        // optional set description shown in library
    var leftTitle:    String?
    var rightTitle:   String?
    var displayMode:  DisplayMode
    var accessTier:   AccessTier
    var items:        [FSPair]
    var updatedAt:    Date
    var createdAt:    Date

    init(id: String, collectionId: String, title: String? = nil, subtitle: String? = nil,
         description: String? = nil,
         leftTitle: String? = nil, rightTitle: String? = nil,
         displayMode: DisplayMode, accessTier: AccessTier,
         items: [FSPair], updatedAt: Date, createdAt: Date) {
        self.id           = id
        self.collectionId = collectionId
        self.title        = title
        self.subtitle     = subtitle
        self.description  = description
        self.leftTitle    = leftTitle
        self.rightTitle   = rightTitle
        self.displayMode  = displayMode
        self.accessTier   = accessTier
        self.items        = items
        self.updatedAt    = updatedAt
        self.createdAt    = createdAt
    }
}

// MARK: - FSPair

struct FSPair: Codable, Identifiable {
    var id:    String
    var left:  FSPairSide?
    var right: FSPairSide?
}

// MARK: - FSPairSide

struct FSPairSide: Codable {
    var text: String?
}

// MARK: - FirestoreID

enum FirestoreID {
    static func make(name: String, uuid: UUID = UUID()) -> String {
        let clean = name
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        let prefix = String(clean.prefix(11)).padding(toLength: 11, withPad: "_", startingAt: 0)
        return "\(prefix)_\(uuid.uuidString)"
    }
}
