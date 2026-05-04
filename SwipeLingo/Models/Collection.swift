import Foundation
import SwiftData

// Sets belonging to this collection are queried via: #Predicate<CardSet> { $0.collectionId == collection.id }
// PairsSets belonging to this collection are queried via: #Predicate<PairsSet> { $0.collectionId == collection.id }
@Model
final class Collection {
    var id: UUID
    var name: String
    var icon: String?       // SF Symbol name or emoji
    var isOwned: Bool       // true = user owns (not paywalled); false = premium/Firebase
    // true  → created by the user (My Sets, Inbox, custom collections) — no CEFR badge, no Firebase sync
    // false → developer-seeded content (IELTS, Psychology) — show CEFR badge in set list
    var isUserCreated: Bool = true
    var typeRaw: String     = CollectionType.cards.rawValue  // "cards" | "pairs" — CloudKit-safe
    var updatedAt: Date     = Date.epoch                // обновляется Admin Tool при публикации
    var createdAt: Date
    var firestoreId: String? = nil                      // Firestore document ID for sync deduplication

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

// CollectionType — см. Models/CollectionType.swift
