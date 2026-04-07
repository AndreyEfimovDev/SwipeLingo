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

struct FSCollection: Codable, Identifiable {
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

// MARK: - FSCardSet

struct FSCardSet: Codable, Identifiable {
    var id: String              // firestoreId
    var collectionId: String    // firestoreId родительской Collection
    var name: String
    var level: String           // CEFRLevel.rawValue
    var accessTierRaw: String   // AccessTier.rawValue: "free" | "go" | "pro"
    var isPublished: Bool
    var updatedAt: Date
    var createdAt: Date

    var accessTier: AccessTier {
        AccessTier(rawValue: accessTierRaw) ?? .free
    }
}

// MARK: - FSCard

struct FSCard: Codable, Identifiable {
    var id: String              // firestoreId
    var setId: String           // firestoreId родительского CardSet
    var en: String
    var item: String
    var sampleEN: [String]      // Firestore нативно поддерживает [String]
    var sampleItem: [String]
    var level: String           // CEFRLevel.rawValue
    var accessTierRaw: String   // AccessTier.rawValue
    var isPublished: Bool
    var updatedAt: Date
    var createdAt: Date

    var accessTier: AccessTier {
        AccessTier(rawValue: accessTierRaw) ?? .free
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
