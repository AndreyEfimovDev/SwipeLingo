import Foundation
import SwiftData

@Model
final class Card {
    var id: UUID
    var en: String
    var item: String
    var sampleEN: [String]
    var sampleItem: [String]
    var status: CardStatus
    var isFavorite: Bool
    var tags: [String]
    // SRS fields (SM-2)
    var easeFactor: Double
    var interval: Int
    var repetitions: Int
    var dueDate: Date
    var lastReviewed: Date
    // Metadata
    var createdAt: Date
    var importedAt: Date?
    var setId: UUID

    init(
        id: UUID = UUID(),
        en: String,
        item: String,
        sampleEN: [String] = [],
        sampleItem: [String] = [],
        status: CardStatus = .active,
        isFavorite: Bool = false,
        tags: [String] = [],
        easeFactor: Double = 2.5,
        interval: Int = 1,
        repetitions: Int = 0,
        dueDate: Date = .now,
        lastReviewed: Date = .now,
        createdAt: Date = .now,
        importedAt: Date? = nil,
        setId: UUID
    ) {
        self.id = id
        self.en = en
        self.item = item
        self.sampleEN = sampleEN
        self.sampleItem = sampleItem
        self.status = status
        self.isFavorite = isFavorite
        self.tags = tags
        self.easeFactor = easeFactor
        self.interval = interval
        self.repetitions = repetitions
        self.dueDate = dueDate
        self.lastReviewed = lastReviewed
        self.createdAt = createdAt
        self.importedAt = importedAt
        self.setId = setId
    }
}
