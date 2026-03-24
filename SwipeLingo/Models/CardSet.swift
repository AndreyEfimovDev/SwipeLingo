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

    init(
        id: UUID = UUID(),
        name: String,
        collectionId: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.collectionId = collectionId
        self.createdAt = createdAt
    }
}
