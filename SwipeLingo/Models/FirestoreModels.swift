import Foundation

// MARK: - FirestoreModels
//
// Codable-структуры для слоя Firestore. Используются в двух местах:
//   1. SwipeLingoAdmin — создание/редактирование/публикация контента
//   2. FirestoreImportService (основное приложение) — загрузка и конвертация в SwiftData-модели
//
// Отличия от SwiftData @Model классов:
//   - id: String (firestoreId = NAMEPREFIX_UUID), не UUID
//   - isPublished: Bool — черновик vs опубликован
//   - Нет SRS-полей (они пользовательские, хранятся только в SwiftData)
//   - [String] и вложенные объекты хранятся нативно (Firestore поддерживает)

// MARK: - FSCollection

struct FSCollection: Codable, Identifiable, Hashable {
    var id: String              // firestoreId: NAMEPREFIX_UUID
    var name: String
    var icon: String?           // SF Symbol name or emoji
    var typeRaw: String         // CollectionType.rawValue: "cards" | "pairs"
    var isPublished: Bool       // false = черновик, iOS не синхронизирует
    var updatedAt: Date
    var createdAt: Date

    var collectionType: CollectionType {
        CollectionType(rawValue: typeRaw) ?? .cards
    }
}

// MARK: - SetDeployStatus

enum SetDeployStatus: String, Codable, CaseIterable {
    case draft      // черновик, ещё не готов
    case ready      // помечен вручную как готов к деплою
    case live       // загружен в Firebase
    case outdated   // в Firebase, но есть локальные изменения

    var label: String {
        switch self {
        case .draft:    "Draft"
        case .ready:    "Ready"
        case .live:     "Live"
        case .outdated: "Outdated"
        }
    }

    var color: String {
        switch self {
        case .draft:    "secondary"
        case .ready:    "blue"
        case .live:     "green"
        case .outdated: "orange"
        }
    }
}

// MARK: - FSCardSet

struct FSCardSet: Codable, Identifiable, Hashable {
    var id: String              // firestoreId
    var collectionId: String    // firestoreId родительской Collection
    var name: String
    var level: String           // CEFRLevel.rawValue
    var accessTierRaw: String   // AccessTier.rawValue: "free" | "go" | "pro"
    var deployStatusRaw: String
    var isPublished: Bool
    var updatedAt: Date
    var createdAt: Date

    var accessTier: AccessTier {
        AccessTier(rawValue: accessTierRaw) ?? .free
    }

    var deployStatus: SetDeployStatus {
        get { SetDeployStatus(rawValue: deployStatusRaw) ?? .draft }
        set { deployStatusRaw = newValue.rawValue }
    }

    // Кастомный декодер: deployStatusRaw опциональный для совместимости со старыми данными
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        collectionId    = try c.decode(String.self, forKey: .collectionId)
        name            = try c.decode(String.self, forKey: .name)
        level           = try c.decode(String.self, forKey: .level)
        accessTierRaw   = try c.decode(String.self, forKey: .accessTierRaw)
        deployStatusRaw = try c.decodeIfPresent(String.self, forKey: .deployStatusRaw) ?? SetDeployStatus.draft.rawValue
        isPublished     = try c.decode(Bool.self,   forKey: .isPublished)
        updatedAt       = try c.decode(Date.self,   forKey: .updatedAt)
        createdAt       = try c.decode(Date.self,   forKey: .createdAt)
    }

    // Явный memberwise init (нужен после кастомного декодера)
    init(id: String, collectionId: String, name: String, level: String,
         accessTierRaw: String, deployStatusRaw: String = SetDeployStatus.draft.rawValue,
         isPublished: Bool, updatedAt: Date, createdAt: Date) {
        self.id              = id
        self.collectionId    = collectionId
        self.name            = name
        self.level           = level
        self.accessTierRaw   = accessTierRaw
        self.deployStatusRaw = deployStatusRaw
        self.isPublished     = isPublished
        self.updatedAt       = updatedAt
        self.createdAt       = createdAt
    }
}

// MARK: - FSCard

struct FSCard: Codable, Identifiable, Hashable {
    var id: String              // firestoreId
    var setId: String           // firestoreId родительского CardSet
    var en: String
    var transcription: String   // MW-нотация или IPA, пустая если фраза или не найдено
    var translations: [String: String]          // ["ru": "серендипность", "zh": "天缘巧合", ...]
    var sampleEN: [String]                      // Firestore нативно поддерживает [String]
    var sampleTranslations: [String: [String]]  // ["ru": ["пример1", "пример2"], "zh": ["示例1"]]
    var tag: String              // контекстная группа, e.g. "Family Members" — lowercase при сравнении
    var level: String           // CEFRLevel.rawValue
    var accessTierRaw: String   // AccessTier.rawValue
    var isPublished: Bool
    var updatedAt: Date
    var createdAt: Date

    var accessTier: AccessTier {
        AccessTier(rawValue: accessTierRaw) ?? .free
    }

    /// Перевод для указанного языка (пустая строка если не заполнен)
    func translation(for language: NativeLanguage) -> String {
        translations[language.langId] ?? ""
    }

    /// Примеры перевода для указанного языка
    func sampleTranslation(for language: NativeLanguage) -> [String] {
        sampleTranslations[language.langId] ?? []
    }
}

// MARK: - FSPairsSet

struct FSPairsSet: Codable, Identifiable {
    var id: String              // firestoreId
    var collectionId: String    // firestoreId родительской Collection
    var title: String?
    var subtitle: String?
    var leftTitle: String?      // название левой колонки  ("B2", "Basic")
    var rightTitle: String?     // название правой колонки ("C1", "Advanced")
    var displayModeRaw: String  // DisplayMode.rawValue: "sequential" | "parallel"
    var accessTierRaw: String   // AccessTier.rawValue
    var items: [FSPair]         // Firestore нативно поддерживает массив объектов
    var isPublished: Bool
    var updatedAt: Date
    var createdAt: Date

    var displayMode: DisplayMode {
        DisplayMode(rawValue: displayModeRaw) ?? .parallel
    }

    var accessTier: AccessTier {
        AccessTier(rawValue: accessTierRaw) ?? .free
    }
}

// MARK: - FSPair

struct FSPair: Codable, Identifiable {
    var id: String              // UUID().uuidString
    var left: FSPairSide?
    var right: FSPairSide?
}

// MARK: - FSPairSide

struct FSPairSide: Codable {
    var text: String?
}

// MARK: - FirestoreID

// Утилита для вычисления firestoreId из имени и UUID.
// Формат: NAMEPREFIX_UUID
// Prefix: первые 11 символов имени (uppercase, только буквы и цифры, дополнение "_" справа)
// Пример: "IELTSVOCABL_550e8400-e29b-41d4-a716-446655440000"

enum FirestoreID {
    static func make(name: String, uuid: UUID = UUID()) -> String {
        let clean = name
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        let prefix = String(clean.prefix(11)).padding(toLength: 11, withPad: "_", startingAt: 0)
        return "\(prefix)_\(uuid.uuidString)"
    }
}
