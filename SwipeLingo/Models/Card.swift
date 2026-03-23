import Foundation
import SwiftData

// MARK: - Array ↔ String helpers
//
// SwiftData + CloudKit cannot materialise Array<String> as an Objective-C
// attribute type. We persist each [String] field as a single String with
// U+001F (ASCII Unit Separator) as the delimiter — a control character
// that never appears in natural text.

private let kSep = "\u{001F}"

private func encodeArray(_ array: [String]) -> String {
    array.joined(separator: kSep)
}

private func decodeArray(_ raw: String) -> [String] {
    guard !raw.isEmpty else { return [] }
    return raw.components(separatedBy: kSep)
}

// MARK: - Card

@Model
final class Card {
    var id: UUID
    var en: String
    var item: String

    // Backing stores — String is fully CloudKit-compatible
    private var sampleENRaw:   String
    private var sampleItemRaw: String
    private var tagsRaw:       String

    var status: CardStatus
    var isFavorite: Bool

    // SRS fields (SM-2)
    var easeFactor:  Double
    var interval:    Int
    var repetitions: Int
    var dueDate:     Date
    var lastReviewed: Date

    // Dictionary cache — plain String, CloudKit compatible (empty = not yet fetched)
    var dictTranscription: String
    var dictAudioURL:      String
    var dictDefinition:    String

    // Metadata
    var createdAt:  Date
    var importedAt: Date?
    var setId:      UUID

    // MARK: Computed [String] accessors (same public API as before)

    var sampleEN: [String] {
        get { decodeArray(sampleENRaw) }
        set { sampleENRaw = encodeArray(newValue) }
    }

    var sampleItem: [String] {
        get { decodeArray(sampleItemRaw) }
        set { sampleItemRaw = encodeArray(newValue) }
    }

    var tags: [String] {
        get { decodeArray(tagsRaw) }
        set { tagsRaw = encodeArray(newValue) }
    }

    // MARK: Init

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
        dictTranscription: String = "",
        dictAudioURL: String = "",
        dictDefinition: String = "",
        createdAt: Date = .now,
        importedAt: Date? = nil,
        setId: UUID
    ) {
        self.id            = id
        self.en            = en
        self.item          = item
        self.sampleENRaw   = encodeArray(sampleEN)
        self.sampleItemRaw = encodeArray(sampleItem)
        self.status        = status
        self.isFavorite    = isFavorite
        self.tagsRaw       = encodeArray(tags)
        self.easeFactor    = easeFactor
        self.interval      = interval
        self.repetitions   = repetitions
        self.dueDate       = dueDate
        self.lastReviewed      = lastReviewed
        self.dictTranscription = dictTranscription
        self.dictAudioURL      = dictAudioURL
        self.dictDefinition    = dictDefinition
        self.createdAt         = createdAt
        self.importedAt        = importedAt
        self.setId             = setId
    }
}
