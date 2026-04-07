import Foundation
import SwiftUI
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
    var id: UUID = UUID()
    var en: String = ""
    var item: String = ""

    // Backing stores — String is fully CloudKit-compatible
    private var sampleENRaw:   String = ""
    private var sampleItemRaw: String = ""
    private var tagsRaw:       String = ""
    private var synonymsRaw:   String = ""

    var status: CardStatus = CardStatus.active
    var isFavorite: Bool = false

    // SRS fields (SM-2)
    var easeFactor:  Double = 2.5
    var interval:    Int    = 1
    var repetitions: Int    = 0
    var dueDate:     Date   = Date.distantFuture  // новая карточка не в Due до первой оценки
    var lastReviewed: Date  = Date.distantPast

    // Dictionary cache — plain String, CloudKit compatible (empty = not yet fetched)
    var dictTranscription: String = ""
    var dictAudioURL:      String = ""
    var dictDefinition:    String = ""

    // CEFR level — stored as String for CloudKit/SwiftData compatibility
    var level: String = CEFRLevel.a0a1.rawValue

    var cefrLevel: CEFRLevel {
        get { CEFRLevel(rawValue: level) ?? .a0a1 }
        set { level = newValue.rawValue }
    }

    // Metadata
    var createdAt:  Date  = Date.now
    var updatedAt:  Date  = Date.distantPast  // обновляется Admin Tool при публикации
    var importedAt: Date? = nil
    var setId:      UUID  = UUID()

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

    var synonyms: [String] {
        get { decodeArray(synonymsRaw) }
        set { synonymsRaw = encodeArray(newValue) }
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
        synonyms: [String] = [],
        easeFactor: Double = 2.5,
        interval: Int = 1,
        repetitions: Int = 0,
        dueDate: Date = .distantFuture,
        lastReviewed: Date = .distantPast,
        dictTranscription: String = "",
        dictAudioURL: String = "",
        dictDefinition: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .distantPast,
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
        self.synonymsRaw   = encodeArray(synonyms)
        self.easeFactor    = easeFactor
        self.interval      = interval
        self.repetitions   = repetitions
        self.dueDate       = dueDate
        self.lastReviewed      = lastReviewed
        self.dictTranscription = dictTranscription
        self.dictAudioURL      = dictAudioURL
        self.dictDefinition    = dictDefinition
        self.createdAt         = createdAt
        self.updatedAt         = updatedAt
        self.importedAt        = importedAt
        self.setId             = setId
    }
}

enum CardStatus: String, Codable, CaseIterable {
    case active
    case learnt
    case deleted
    
    var color: Color {
        switch self {
        case .active: Color.myColors.myBlue
        case .learnt: Color.myColors.myGreen
        case .deleted: Color.myColors.myRed
        }
    }
}
