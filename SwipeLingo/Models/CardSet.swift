import Foundation
import SwiftData

// Named CardSet because "Set" is reserved in the Swift standard library.
// Cards belonging to this set are queried via: #Predicate<Card> { $0.setId == cardSet.id }
@Model
final class CardSet {
    var id: UUID
    var name: String
    var collectionId: UUID
    var createdAt: Date

    // false = developer content (IELTS sets, Psychology sets)
    // true  = user-created content (sets inside My Sets)
    var isUserCreated: Bool = true

    // CEFR level — stored as String for CloudKit/SwiftData compatibility
    var level: String = CEFRLevel.a0a1.rawValue

    var cefrLevel: CEFRLevel {
        get { CEFRLevel(rawValue: level) ?? .a0a1 }
        set { level = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        collectionId: UUID,
        level: CEFRLevel = .a0a1,
        isUserCreated: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.collectionId = collectionId
        self.level = level.rawValue
        self.isUserCreated = isUserCreated
        self.createdAt = createdAt
    }
}
