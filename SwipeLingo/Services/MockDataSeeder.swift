import Foundation
import SwiftData

// MARK: - MockDataSeeder
//
// Ensures system collections (Inbox, My Sets) always exist on every launch.
// Developer content (Collections → CardSets → Cards) is handled by FirestoreImportService.

struct MockDataSeeder {

    // MARK: - System Collections

    /// Creates "My Sets" and "Inbox" if they are missing.
    /// Safe to call on every launch — only inserts what is absent.
    static func ensureSystemCollections(into context: ModelContext) {
        let existing = context.fetchWithErrorHandling(FetchDescriptor<Collection>())
        let names = Set(existing.map { $0.name })

        if !names.contains("My Sets") {
            let mySets = Collection(name: "My Sets", icon: "folder", isOwned: true, isUserCreated: true)
            context.insert(mySets)
        }

        var inboxSet: CardSet?

        if !names.contains("Inbox") {
            let inbox = Collection(name: "Inbox", icon: "tray", isOwned: true, isUserCreated: true)
            context.insert(inbox)
            let set = CardSet(name: "Inbox", collectionId: inbox.id)
            context.insert(set)
            inboxSet = set
        } else if let inbox = existing.first(where: { $0.name == "Inbox" }) {
            let sets = context.fetchWithErrorHandling(FetchDescriptor<CardSet>())
            if let existing = sets.first(where: { $0.collectionId == inbox.id }) {
                inboxSet = existing
            } else {
                let set = CardSet(name: "Inbox", collectionId: inbox.id)
                context.insert(set)
                inboxSet = set
            }
        }

        // MARK: Inbox stub cards
        // TODO: Remove — real cards arrive from share extension / clipboard.
        #warning("STUB: Inbox seed cards are temporary. Remove before App Store release.")
        if let set = inboxSet {
            let allCards = context.fetchWithErrorHandling(FetchDescriptor<Card>())
            let hasInboxCards = allCards.contains { $0.setId == set.id }
            if !hasInboxCards {
                let stubs: [Card] = [
                    Card(en: "Serendipity",   item: "", setId: set.id),
                    Card(en: "Idiosyncratic", item: "", setId: set.id),
                    Card(en: "Perseverance",  item: "", setId: set.id),
                ]
                for card in stubs { context.insert(card) }
            }
        }

        context.saveWithErrorHandling()
    }

    // MARK: - Dev Mock Collection

    /// Seeds a mock developer collection with cards across multiple CEFR levels.
    /// Safe to call on every launch — skips if already present.
    #warning("STUB: Mock dev collection is for UI testing only. Remove before App Store release.")
    static func ensureMockDevCollection(into context: ModelContext) {
        let existing = context.fetchWithErrorHandling(FetchDescriptor<Collection>())
        guard !existing.contains(where: { $0.name == "Academic Words" }) else { return }

        let collection = Collection(name: "Academic Words", icon: "book", isOwned: true, isUserCreated: false)
        context.insert(collection)

        let sets: [(name: String, level: CEFRLevel, cards: [(en: String, item: String)])] = [
            (
                name: "Foundations", level: .a2,
                cards: [
                    ("Concept",     "понятие, концепция"),
                    ("Factor",      "фактор, причина"),
                    ("Source",      "источник"),
                    ("Process",     "процесс"),
                    ("Structure",   "структура"),
                ]
            ),
            (
                name: "Core Academic", level: .b1,
                cards: [
                    ("Analyse",     "анализировать"),
                    ("Approach",    "подход"),
                    ("Constitute",  "составлять, образовывать"),
                    ("Context",     "контекст"),
                    ("Evidence",    "доказательство, свидетельство"),
                ]
            ),
            (
                name: "Upper Academic", level: .b2,
                cards: [
                    ("Albeit",      "хотя, несмотря на то что"),
                    ("Comprehensive","всесторонний, полный"),
                    ("Derive",      "происходить, получать"),
                    ("Implicit",    "подразумеваемый, неявный"),
                    ("Rationale",   "обоснование, логика"),
                ]
            ),
            (
                name: "Advanced", level: .c1,
                cards: [
                    ("Nuance",      "нюанс, оттенок"),
                    ("Perpetuate",  "увековечивать, сохранять"),
                    ("Dichotomy",   "дихотомия, противопоставление"),
                    ("Pragmatic",   "прагматичный"),
                    ("Ubiquitous",  "повсеместный, вездесущий"),
                ]
            ),
        ]

        for setData in sets {
            let cardSet = CardSet(name: setData.name, collectionId: collection.id)
            cardSet.level = setData.level.rawValue
            context.insert(cardSet)

            for cardData in setData.cards {
                let card = Card(en: cardData.en, item: cardData.item, setId: cardSet.id)
                card.level = setData.level.rawValue
                context.insert(card)
            }
        }

        context.saveWithErrorHandling()
    }
}
