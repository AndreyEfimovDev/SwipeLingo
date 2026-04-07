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

        let sets: [(name: String, level: CEFRLevel, accessTier: AccessTier, cards: [(en: String, item: String)])] = [
            (
                name: "Foundations", level: .a2, accessTier: .free,
                cards: [
                    ("Concept",     "понятие, концепция"),
                    ("Factor",      "фактор, причина"),
                    ("Source",      "источник"),
                    ("Process",     "процесс"),
                    ("Structure",   "структура"),
                ]
            ),
            (
                name: "Core Academic", level: .b1, accessTier: .go,
                cards: [
                    ("Analyse",     "анализировать"),
                    ("Approach",    "подход"),
                    ("Constitute",  "составлять, образовывать"),
                    ("Context",     "контекст"),
                    ("Evidence",    "доказательство, свидетельство"),
                ]
            ),
            (
                name: "Upper Academic", level: .b2, accessTier: .go,
                cards: [
                    ("Albeit",      "хотя, несмотря на то что"),
                    ("Comprehensive","всесторонний, полный"),
                    ("Derive",      "происходить, получать"),
                    ("Implicit",    "подразумеваемый, неявный"),
                    ("Rationale",   "обоснование, логика"),
                ]
            ),
            (
                name: "Advanced", level: .c1, accessTier: .pro,
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
            let cardSet = CardSet(name: setData.name, collectionId: collection.id,
                                  accessTier: setData.accessTier)
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
                ("Presentations", .b1, .go,  [("Outline", "план, схема"), ("Takeaway", "главный вывод"), ("Benchmark", "эталон, ориентир")]),
                ("Negotiations",  .b2, .pro, [("Agenda", "повестка дня"), ("Leverage", "влияние, рычаг"), ("Stakeholder", "заинтересованная сторона")]),
            ],
            into: context
        )

        seedMockCuratedCollection(
            name: "Phrasal Verbs",
            icon: "text.bubble",
            sets: [
                ("Movement", .b1, .go,  [("Set off", "отправляться"), ("Break down", "сломаться; расстроиться"), ("Run into", "столкнуться с")]),
                ("Change",   .b2, .pro, [("Phase out", "постепенно отменять"), ("Turn around", "переломить ситуацию"), ("Give up", "сдаться")]),
            ],
            into: context
        )
    }

    // MARK: - Mock PairsSets

    /// Seeds mock Pairs sets for UI testing.
    /// Safe to call on every launch — skips if any PairsSet already exists.
    #warning("STUB: Mock PairsSets are for UI testing only. Remove before App Store release.")
    static func ensureMockPairsSets(into context: ModelContext) {
        let existing = context.fetchWithErrorHandling(FetchDescriptor<PairsSet>())
        guard existing.isEmpty else { return }

        // Set 1: B2 → C1, sequential mode (left появляется первым, потом right)
        let set1 = PairsSet(
            title: "B2 → C1 Vocabulary",
            subtitle: "Upgrade your word choice",
            leftTitle: "B2",
            rightTitle: "C1",
            displayMode: .sequential,
            accessTier: .free,
            items: [
                Pair(left: PairSide(text: "important"),    right: PairSide(text: "pivotal")),
                Pair(left: PairSide(text: "use"),          right: PairSide(text: "utilize")),
                Pair(left: PairSide(text: "show"),         right: PairSide(text: "demonstrate")),
                Pair(left: PairSide(text: "think about"),  right: PairSide(text: "contemplate")),
                Pair(left: PairSide(text: "change"),       right: PairSide(text: "transform")),
                Pair(left: PairSide(text: "get better"),   right: PairSide(text: "improve")),
            ]
        )
        context.insert(set1)

        // Set 2: Basic → Advanced, parallel mode (оба появляются одновременно)
        let set2 = PairsSet(
            title: "Everyday → Advanced",
            subtitle: "Replace weak intensifiers",
            leftTitle: "Basic",
            rightTitle: "Advanced",
            displayMode: .parallel,
            accessTier: .go,
            items: [
                Pair(left: PairSide(text: "very tired"),     right: PairSide(text: "exhausted")),
                Pair(left: PairSide(text: "very happy"),     right: PairSide(text: "elated")),
                Pair(left: PairSide(text: "very angry"),     right: PairSide(text: "furious")),
                Pair(left: PairSide(text: "very sad"),       right: PairSide(text: "despondent")),
                Pair(left: PairSide(text: "very surprised"), right: PairSide(text: "astonished")),
                Pair(left: PairSide(text: "very scared"),    right: PairSide(text: "terrified")),
            ]
        )
        context.insert(set2)

        // Set 3: Informal → Formal, parallel mode, Pro tier (тест badge + длинный список для тест скролла)
        let set3 = PairsSet(
            title: "Informal → Formal",
            subtitle: "Business writing register",
            leftTitle: "Informal",
            rightTitle: "Formal",
            displayMode: .parallel,
            accessTier: .pro,
            items: [
                Pair(left: PairSide(text: "get in touch"),  right: PairSide(text: "contact")),
                Pair(left: PairSide(text: "find out"),      right: PairSide(text: "ascertain")),
                Pair(left: PairSide(text: "go up"),         right: PairSide(text: "increase")),
                Pair(left: PairSide(text: "look into"),     right: PairSide(text: "investigate")),
                Pair(left: PairSide(text: "set up"),        right: PairSide(text: "establish")),
                Pair(left: PairSide(text: "think about"),   right: PairSide(text: "consider")),
                Pair(left: PairSide(text: "make sure"),     right: PairSide(text: "ensure")),
                Pair(left: PairSide(text: "talk about"),    right: PairSide(text: "discuss")),
                Pair(left: PairSide(text: "get rid of"),    right: PairSide(text: "eliminate")),
                Pair(left: PairSide(text: "bring up"),      right: PairSide(text: "raise")),
                Pair(left: PairSide(text: "point out"),     right: PairSide(text: "indicate")),
                Pair(left: PairSide(text: "go along with"), right: PairSide(text: "comply with")),
                Pair(left: PairSide(text: "check out"),     right: PairSide(text: "examine")),
                Pair(left: PairSide(text: "come up with"),  right: PairSide(text: "propose")),
                Pair(left: PairSide(text: "wrap up"),       right: PairSide(text: "conclude")),
            ]
        )
        context.insert(set3)

        context.saveWithErrorHandling()
    }

    private static func seedMockCuratedCollection(
        name: String,
        icon: String,
        sets: [(name: String, level: CEFRLevel, accessTier: AccessTier, cards: [(String, String)])],
        into context: ModelContext
    ) {
        let existing = context.fetchWithErrorHandling(FetchDescriptor<Collection>())
        guard !existing.contains(where: { $0.name == name }) else { return }

        let collection = Collection(name: name, icon: icon, isOwned: true, isUserCreated: false)
        context.insert(collection)

        for setData in sets {
            let cardSet = CardSet(name: setData.name, collectionId: collection.id,
                                  accessTier: setData.accessTier)
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
