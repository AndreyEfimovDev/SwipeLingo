import Foundation
import SwiftUI
import SwiftData

// MARK: - Array ↔ String helpers
//
// SwiftData + CloudKit не могут материализовать Array<String> как атрибут
// Objective-C типа. Каждое поле [String] храним как одну String с
// разделителем U+001F (ASCII Unit Separator) — управляющий символ,
// который никогда не встречается в обычном тексте.

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

    // Хранилище — String полностью совместим с CloudKit
    private var sampleENRaw:       String = ""
    private var sampleItemRaw:     String = ""
    private var userSampleENRaw:   String = ""  // примеры, добавленные пользователем (сохраняются при Firestore-синке)
    private var userSampleItemRaw: String = ""
    private var tagsRaw:           String = ""
    private var synonymsRaw:       String = ""

    var status: CardStatus = CardStatus.active
    var isFavorite: Bool = false

    // Поля SRS (SM-2)
    var easeFactor:  Double = 2.5
    var interval:    Int    = 1
    var repetitions: Int    = 0
    var dueDate:     Date   = Date.farFuture  // новая карточка не в Due до первой оценки
    var lastReviewed: Date  = Date.epoch

    // Кэш словаря — обычная String, совместимая с CloudKit (пусто = ещё не загружено)
    var dictTranscription: String = ""
    var dictAudioURL:      String = ""
    var dictDefinition:    String = ""

    // CEFR-уровень — хранится как String для совместимости с CloudKit/SwiftData
    var level: String = CEFRLevel.a1.rawValue

    var cefrLevel: CEFRLevel {
        get { CEFRLevel(rawValue: level) ?? .a1 }
        set { level = newValue.rawValue }
    }

    // Метаданные
    var createdAt:  Date  = Date.now
    var updatedAt:  Date  = Date.epoch  // обновляется Admin Tool при публикации
    var importedAt: Date? = nil
    var setId:      UUID  = UUID()
    var firestoreId: String? = nil      // ID документа Firestore для дедупликации при синке
    var isNew:      Bool  = false       // true = импортирована из Firestore, но ещё не показана в сессии обучения

    // MARK: Вычисляемые доступы к [String] (тот же публичный API, что и раньше)

    var sampleEN: [String] {
        get { decodeArray(sampleENRaw) }
        set { sampleENRaw = encodeArray(newValue) }
    }

    var sampleItem: [String] {
        get { decodeArray(sampleItemRaw) }
        set { sampleItemRaw = encodeArray(newValue) }
    }

    /// Примеры, добавленные пользователем из DictionaryLookupView — сохраняются при Firestore-синке.
    var userSampleEN: [String] {
        get { decodeArray(userSampleENRaw) }
        set { userSampleENRaw = encodeArray(newValue) }
    }

    var userSampleItem: [String] {
        get { decodeArray(userSampleItemRaw) }
        set { userSampleItemRaw = encodeArray(newValue) }
    }

    /// Примеры Firestore + пользовательские вместе, для отображения.
    var allSampleEN: [String]   { sampleEN + userSampleEN }
    var allSampleItem: [String] { sampleItem + userSampleItem }

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
        dueDate: Date = .farFuture,
        lastReviewed: Date = .epoch,
        dictTranscription: String = "",
        dictAudioURL: String = "",
        dictDefinition: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .epoch,
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
