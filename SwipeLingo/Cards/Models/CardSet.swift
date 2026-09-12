import Foundation
import SwiftData

// Названо CardSet, потому что "Set" зарезервировано в стандартной библиотеке Swift.
// Карточки, принадлежащие этому сету, запрашиваются через: #Predicate<Card> { $0.setId == cardSet.id }
@Model
final class CardSet {
    var id: UUID = UUID()
    var name: String = ""
    var collectionId: UUID = UUID()
    var createdAt: Date = Date()

    // false = контент от разработчика (IELTS-сеты, Psychology-сеты)
    // true  = пользовательский контент (сеты внутри My Sets)
    var isUserCreated: Bool = true

    // опциональное развёрнутое описание, показывается в экране деталей сета
    var setDescription: String? = nil

    // CEFR-уровень — хранится как String для совместимости с CloudKit/SwiftData
    var level: String = CEFRLevel.a1.rawValue

    // Уровень доступа — хранится как String для совместимости с CloudKit/SwiftData
    var accessTierRaw: String = AccessTier.free.rawValue

    var updatedAt: Date = Date.epoch  // обновляется Admin Tool при публикации
    var firestoreId: String? = nil   // ID документа Firestore для дедупликации при синке
    var isSoftDeleted: Bool = false  // мягкое удаление: скрыт в UI, не удаляется из SwiftData; блокирует sync

    var cefrLevel: CEFRLevel {
        get { CEFRLevel(rawValue: level) ?? .a1 }
        set { level = newValue.rawValue }
    }

    var accessTier: AccessTier {
        get { AccessTier(rawValue: accessTierRaw) ?? .free }
        set { accessTierRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        collectionId: UUID,
        level: CEFRLevel = .a1,
        isUserCreated: Bool = true,
        accessTier: AccessTier = .free,
        setDescription: String? = nil,
        updatedAt: Date = .epoch,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.collectionId = collectionId
        self.level = level.rawValue
        self.isUserCreated = isUserCreated
        self.accessTierRaw = accessTier.rawValue
        self.setDescription = setDescription
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}
