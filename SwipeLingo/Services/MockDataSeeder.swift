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

        if !existing.contains(where: { $0.name == "Academic Words" }) {
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
        } // end if Academic Words

        // Extra mock collections to test "Show all" in Curated section
        seedMockCuratedCollection(
            name: "Business English",
            icon: "briefcase",
            sets: [
                ("Negotiations", .b2, [("Agenda", "повестка дня"), ("Leverage", "влияние, рычаг"), ("Stakeholder", "заинтересованная сторона")]),
                ("Presentations", .b1, [("Outline", "план, схема"), ("Takeaway", "главный вывод"), ("Benchmark", "эталон, ориентир")]),
            ],
            into: context
        )

        seedMockCuratedCollection(
            name: "Phrasal Verbs",
            icon: "text.bubble",
            sets: [
                ("Movement", .b1, [("Set off", "отправляться"), ("Break down", "сломаться; расстроиться"), ("Run into", "столкнуться с")]),
                ("Change", .b2, [("Phase out", "постепенно отменять"), ("Turn around", "переломить ситуацию"), ("Give up", "сдаться")]),
            ],
            into: context
        )
    }

    // MARK: - Mock DynamicSets

    /// Seeds mock English+ sets for UI testing.
    /// Safe to call on every launch — skips if any DynamicSet already exists.
    #warning("STUB: Mock DynamicSets are for UI testing only. Remove before App Store release.")
    static func ensureMockDynamicSets(into context: ModelContext) {
        let existing = context.fetchWithErrorHandling(FetchDescriptor<DynamicSet>())
        guard existing.isEmpty else { return }

        // Set 1: B2 → C1, sequential mode (left появляется первым, потом right)
        let set1 = DynamicSet(
            title: "B2 → C1 Vocabulary",
            subtitle: "Upgrade your word choice",
            leftTitle: "B2",
            rightTitle: "C1",
            displayMode: .sequential,
            accessTier: .free,
            items: [
                DynamicPair(left: DynamicItem(text: "important"),    right: DynamicItem(text: "pivotal")),
                DynamicPair(left: DynamicItem(text: "use"),          right: DynamicItem(text: "utilize")),
                DynamicPair(left: DynamicItem(text: "show"),         right: DynamicItem(text: "demonstrate")),
                DynamicPair(left: DynamicItem(text: "think about"),  right: DynamicItem(text: "contemplate")),
                DynamicPair(left: DynamicItem(text: "change"),       right: DynamicItem(text: "transform")),
                DynamicPair(left: DynamicItem(text: "get better"),   right: DynamicItem(text: "improve")),
            ]
        )
        context.insert(set1)

        // Set 2: Basic → Advanced, parallel mode (оба появляются одновременно)
        let set2 = DynamicSet(
            title: "Everyday → Advanced",
            subtitle: "Replace weak intensifiers",
            leftTitle: "Basic",
            rightTitle: "Advanced",
            displayMode: .parallel,
            accessTier: .free,
            items: [
                DynamicPair(left: DynamicItem(text: "very tired"),     right: DynamicItem(text: "exhausted")),
                DynamicPair(left: DynamicItem(text: "very happy"),     right: DynamicItem(text: "elated")),
                DynamicPair(left: DynamicItem(text: "very angry"),     right: DynamicItem(text: "furious")),
                DynamicPair(left: DynamicItem(text: "very sad"),       right: DynamicItem(text: "despondent")),
                DynamicPair(left: DynamicItem(text: "very surprised"), right: DynamicItem(text: "astonished")),
                DynamicPair(left: DynamicItem(text: "very scared"),    right: DynamicItem(text: "terrified")),
            ]
        )
        context.insert(set2)

        // Set 3: Informal → Formal, parallel mode, Pro tier (тест badge)
        let set3 = DynamicSet(
            title: "Informal → Formal",
            subtitle: "Business writing register",
            leftTitle: "Informal",
            rightTitle: "Formal",
            displayMode: .parallel,
            accessTier: .pro,
            items: [
                DynamicPair(left: DynamicItem(text: "get in touch"), right: DynamicItem(text: "contact")),
                DynamicPair(left: DynamicItem(text: "find out"),     right: DynamicItem(text: "ascertain")),
                DynamicPair(left: DynamicItem(text: "go up"),        right: DynamicItem(text: "increase")),
                DynamicPair(left: DynamicItem(text: "look into"),    right: DynamicItem(text: "investigate")),
                DynamicPair(left: DynamicItem(text: "set up"),       right: DynamicItem(text: "establish")),
            ]
        )
        context.insert(set3)

        context.saveWithErrorHandling()
    }

    private static func seedMockCuratedCollection(
        name: String,
        icon: String,
        sets: [(name: String, level: CEFRLevel, cards: [(String, String)])],
        into context: ModelContext
    ) {
        let existing = context.fetchWithErrorHandling(FetchDescriptor<Collection>())
        guard !existing.contains(where: { $0.name == name }) else { return }

        let collection = Collection(name: name, icon: icon, isOwned: true, isUserCreated: false)
        context.insert(collection)

        for setData in sets {
            let cardSet = CardSet(name: setData.name, collectionId: collection.id)
            cardSet.level = setData.level.rawValue
            context.insert(cardSet)
            for (en, item) in setData.cards {
                let card = Card(en: en, item: item, setId: cardSet.id)
                card.level = setData.level.rawValue
                context.insert(card)
            }
        }
        context.saveWithErrorHandling()
    }
}
