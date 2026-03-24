import Foundation
import SwiftData

// Sets belonging to this collection are queried via: #Predicate<CardSet> { $0.collectionId == collection.id }
@Model
final class Collection {
    var id: UUID
    var name: String
    var icon: String?       // SF Symbol name or emoji
    var isOwned: Bool       // true = user-created; false = purchased from Firebase
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        isOwned: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isOwned = isOwned
        self.createdAt = createdAt
    }
}
