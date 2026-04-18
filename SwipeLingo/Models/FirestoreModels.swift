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
    case new      // создан локально, в Firebase нет
    case draft    // изменён после публикации (автоматически)
    case ready    // помечен к публикации вручную
    case live     // синхронизирован с Firebase (автоматически после публикации)
    case deleted  // мягкое удаление — только в Admin, в Firebase удалён

    var label: String {
        switch self {
        case .new:     "New"
        case .draft:   "Draft"
        case .ready:   "Ready"
        case .live:    "Live"
        case .deleted: "Deleted"
        }
    }

    // Backward-compatible decoder: старый store.json может содержать "outdated" → .draft
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "outdated": self = .draft
        default:
            guard let v = SetDeployStatus(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown SetDeployStatus: \(raw)"
                )
            }
            self = v
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
    var description:  String?        // optional set description shown in library
    var cefrLevel:    CEFRLevel
    var accessTier:   AccessTier
    var deployStatus: SetDeployStatus
    var items:        [FSPair]
    var updatedAt:    Date
    var createdAt:    Date

    init(id: String, collectionId: String, title: String? = nil,
         description: String? = nil,
         cefrLevel: CEFRLevel = .b2, accessTier: AccessTier = .free,
         deployStatus: SetDeployStatus = .new,
         items: [FSPair] = [], updatedAt: Date, createdAt: Date) {
        self.id           = id
        self.collectionId = collectionId
        self.title        = title
        self.description  = description
        self.cefrLevel    = cefrLevel
        self.accessTier   = accessTier
        self.deployStatus = deployStatus
        self.items        = items
        self.updatedAt    = updatedAt
        self.createdAt    = createdAt
    }
}

// MARK: - FSPair
//
// Единица контента в PairsSet. Поля и правила отображения:
//
//   left        — основной термин/фраза (короткий, всегда видим)
//   right       — контрпара/синоним   (короткий, в одну строку с left)
//   description — определение/объяснение (полная ширина, новая строка)
//   sample      — пример предложения    (полная ширина, новая строка)
//   tag         — группа внутри сета (аналог Cards.tag, "" = без группы)
//   leftTitle   — заголовок левой колонки для группы (только classic / pairs+sample)
//   rightTitle  — заголовок правой колонки для группы (только classic / pairs+sample)
//
// Типы контента:
//   classic:                 left – right – nil  – nil
//   pairs + sample:          left – right – nil  – sample
//   left-sample:             left – nil   – nil  – sample
//   left-description-sample: left – nil   – desc – sample
//
// Заголовки колонок хранятся на уровне пары, а не сета:
// разные группы внутри одного сета могут иметь разные заголовки.
// В отображении берётся leftTitle/rightTitle первой пары группы.

struct FSPair: Codable, Identifiable {
    var id:          String
    var left:        String?
    var right:       String?
    var description: String?
    var sample:      String?
    var tag:         String
    var leftTitle:   String?      // заголовок левой колонки (на уровне группы)
    var rightTitle:  String?      // заголовок правой колонки (на уровне группы)
    var displayMode: DisplayMode  // parallel / sequential (на уровне группы)

    init(id: String = UUID().uuidString,
         left: String? = nil,
         right: String? = nil,
         description: String? = nil,
         sample: String? = nil,
         tag: String = "",
         leftTitle: String? = nil,
         rightTitle: String? = nil,
         displayMode: DisplayMode = .parallel) {
        self.id          = id
        self.left        = left
        self.right       = right
        self.description = description
        self.sample      = sample
        self.tag         = tag
        self.leftTitle   = leftTitle
        self.rightTitle  = rightTitle
        self.displayMode = displayMode
    }

    // Backward-compatible decoder: новые поля (leftTitle, rightTitle, displayMode)
    // отсутствуют в старых store.json — декодируем с дефолтами.
    init(from decoder: Decoder) throws {
        let c       = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self,      forKey: .id)
        left        = try c.decodeIfPresent(String.self,      forKey: .left)
        right       = try c.decodeIfPresent(String.self,      forKey: .right)
        description = try c.decodeIfPresent(String.self,      forKey: .description)
        sample      = try c.decodeIfPresent(String.self,      forKey: .sample)
        tag         = try c.decodeIfPresent(String.self,      forKey: .tag)         ?? ""
        leftTitle   = try c.decodeIfPresent(String.self,      forKey: .leftTitle)
        rightTitle  = try c.decodeIfPresent(String.self,      forKey: .rightTitle)
        displayMode = try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? .parallel
    }
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
