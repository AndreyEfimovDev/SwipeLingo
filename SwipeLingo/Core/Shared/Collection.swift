import Foundation
import SwiftData

// Сеты, принадлежащие этой коллекции, запрашиваются через: #Predicate<CardSet> { $0.collectionId == collection.id }
// PairsSets, принадлежащие этой коллекции, запрашиваются через: #Predicate<PairsSet> { $0.collectionId == collection.id }
@Model
final class Collection {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String?       // имя SF Symbol или эмодзи
    var isOwned: Bool = true       // true = принадлежит пользователю (не paywalled); false = премиум/Firebase
    // true  → создана пользователем (My Sets, Inbox, пользовательские коллекции) — без бейджа CEFR, без синка с Firebase
    // false → контент от разработчика (IELTS, Psychology) — показывать бейдж CEFR в списке сетов
    var isUserCreated: Bool = true
    var typeRaw: String     = CollectionType.cards.rawValue  // "cards" | "pairs" — CloudKit-safe
    var updatedAt: Date     = Date.epoch                // обновляется Admin Tool при публикации
    var createdAt: Date = Date()
    var firestoreId: String? = nil                      // ID документа Firestore для дедупликации при синке

    var collectionType: CollectionType {
        get { CollectionType(rawValue: typeRaw) ?? .cards }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        isOwned: Bool = true,
        isUserCreated: Bool = true,
        type: CollectionType = .cards,
        updatedAt: Date = .epoch,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isOwned = isOwned
        self.isUserCreated = isUserCreated
        self.typeRaw = type.rawValue
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}

// MARK: - CollectionType
// Тип коллекции определяет какой контент в ней хранится.
// Задаётся при создании в Admin Tool, не меняется после публикации.

enum CollectionType: String, Codable, CaseIterable {
    case cards  // содержит CardSets → Cards (EN↔Native)
    case pairs  // содержит PairsSets → Pairs (EN↔EN)
}
