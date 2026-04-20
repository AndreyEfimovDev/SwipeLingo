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

        let sets: [(name: String, level: CEFRLevel, accessTier: AccessTier, description: String, cards: [(en: String, item: String, tag: String)])] = [
            (
                name: "Foundations", level: .a2, accessTier: .free,
                description: "Essential academic vocabulary for lower-intermediate learners. Covers core nouns used across academic disciplines.",
                cards: [
                    ("Concept",     "понятие, концепция",               "Key Nouns"),
                    ("Factor",      "фактор, причина",                  "Key Nouns"),
                    ("Source",      "источник",                         "Key Nouns"),
                    ("Process",     "процесс",                          "Key Nouns"),
                    ("Structure",   "структура",                        "Key Nouns"),
                ]
            ),
            (
                name: "Core Academic", level: .b1, accessTier: .go,
                description: "High-frequency words from the Academic Word List. Builds the vocabulary foundation needed for academic reading and essay writing.",
                cards: [
                    ("Analyse",     "анализировать",                    "Verbs"),
                    ("Approach",    "подход",                           "Nouns"),
                    ("Constitute",  "составлять, образовывать",         "Verbs"),
                    ("Context",     "контекст",                         "Nouns"),
                    ("Evidence",    "доказательство, свидетельство",    "Nouns"),
                ]
            ),
            (
                name: "Upper Academic", level: .b2, accessTier: .go,
                description: "Advanced linking words, adjectives and verbs that appear frequently in academic papers and formal writing.",
                cards: [
                    ("Albeit",          "хотя, несмотря на то что",     "Linking Words"),
                    ("Comprehensive",   "всесторонний, полный",         "Adjectives"),
                    ("Derive",          "происходить, получать",        "Verbs"),
                    ("Implicit",        "подразумеваемый, неявный",     "Adjectives"),
                    ("Rationale",       "обоснование, логика",          "Nouns"),
                ]
            ),
            (
                name: "Advanced", level: .c1, accessTier: .pro,
                description: "Sophisticated vocabulary for C1-level academic writing and discussion. These words add precision and nuance to your expression.",
                cards: [
                    ("Nuance",      "нюанс, оттенок",                   "Nouns"),
                    ("Perpetuate",  "увековечивать, сохранять",         "Verbs"),
                    ("Dichotomy",   "дихотомия, противопоставление",    "Nouns"),
                    ("Pragmatic",   "прагматичный",                     "Adjectives"),
                    ("Ubiquitous",  "повсеместный, вездесущий",         "Adjectives"),
                ]
            ),
        ]

        for setData in sets {
            let cardSet = CardSet(name: setData.name, collectionId: collection.id,
                                  isUserCreated: false, accessTier: setData.accessTier,
                                  setDescription: setData.description)
            cardSet.level = setData.level.rawValue
            context.insert(cardSet)

            for cardData in setData.cards {
                let card = Card(en: cardData.en, item: cardData.item, setId: cardSet.id)
                card.level = setData.level.rawValue
                card.tags  = [cardData.tag]
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

        // Mock pairs collection
        let col1 = Collection(
            name: "Vocabulary Upgrade",
            icon: "arrow.up.right.circle",
            isOwned: true,
            isUserCreated: false,
            type: .pairs
        )
        let col2 = Collection(
            name: "Phrasal Verbs",
            icon: "text.quote",
            isOwned: true,
            isUserCreated: false,
            type: .pairs
        )
        context.insert(col1)
        context.insert(col2)

        // Set 1: classic — B2 → C1
        let set1 = PairsSet(
            title: "B2 → C1 Vocabulary",
            setDescription: "Replace common B2 words with more precise C1 synonyms. Each pair shows a B2 word you already know alongside a stronger C1 equivalent to add to your active vocabulary.",
            cefrLevel: .b2,
            accessTier: .free,
            items: [
                Pair(left: "important",   right: "pivotal",      leftTitle: "B2", rightTitle: "C1"),
                Pair(left: "use",         right: "utilize"),
                Pair(left: "show",        right: "demonstrate"),
                Pair(left: "think about", right: "contemplate"),
                Pair(left: "change",      right: "transform"),
                Pair(left: "get better",  right: "improve"),
            ],
            collectionId: col1.id
        )
        context.insert(set1)

        // Set 2: classic — Basic → Advanced
        let set2 = PairsSet(
            title: "Everyday → Advanced",
            setDescription: "Ditch weak 'very + adjective' combinations in favour of single expressive words. Native speakers prefer one strong word over a weak intensifier — this set helps you make that switch.",
            cefrLevel: .b1,
            accessTier: .go,
            items: [
                Pair(left: "very tired",     right: "exhausted"),
                Pair(left: "very happy",     right: "elated"),
                Pair(left: "very angry",     right: "furious"),
                Pair(left: "very sad",       right: "despondent"),
                Pair(left: "very surprised", right: "astonished"),
                Pair(left: "very scared",    right: "terrified"),
            ],
            collectionId: col1.id
        )
        context.insert(set2)

        // Set 3: classic — Informal → Formal, Pro
        let set3 = PairsSet(
            title: "Informal → Formal",
            setDescription: "Switch casual spoken phrases for their formal written equivalents. Essential for business emails, reports and academic writing — where register makes all the difference.",
            cefrLevel: .b2,
            accessTier: .pro,
            items: [
                Pair(left: "get in touch",  right: "contact",   leftTitle: "Informal", rightTitle: "Formal"),
                Pair(left: "find out",      right: "ascertain"),
                Pair(left: "go up",         right: "increase"),
                Pair(left: "look into",     right: "investigate"),
                Pair(left: "set up",        right: "establish"),
                Pair(left: "think about",   right: "consider"),
                Pair(left: "make sure",     right: "ensure"),
                Pair(left: "talk about",    right: "discuss"),
                Pair(left: "get rid of",    right: "eliminate"),
                Pair(left: "bring up",      right: "raise"),
                Pair(left: "point out",     right: "indicate"),
                Pair(left: "go along with", right: "comply with"),
                Pair(left: "check out",     right: "examine"),
                Pair(left: "come up with",  right: "propose"),
                Pair(left: "wrap up",       right: "conclude"),
            ],
            collectionId: col1.id
        )
        context.insert(set3)

        // Set 4: pairs+sample + left-sample — Phrasal Verbs (тест типов контента + tag)
        let set4 = PairsSet(
            title: "Phrasal Verbs: Daily",
            setDescription: "Essential phrasal verbs for describing daily routines. Each entry shows the verb, its meaning, and a natural example sentence.",
            cefrLevel: .b1,
            accessTier: .free,
            items: [
                Pair(left: "wake up",    right: "stop sleeping",
                     sample: "I wake up at 7 am every day.",                        tag: "Morning Routine"),
                Pair(left: "get up",     right: "leave your bed",
                     sample: "She gets up immediately after her alarm.",             tag: "Morning Routine"),
                Pair(left: "get dressed", right: "put on clothes",
                     sample: "He got dressed quickly and left for work.",            tag: "Morning Routine"),
                Pair(left: "turn on",    right: "switch on (light, TV, radio)",
                     sample: "I turn on the radio while having breakfast.",          tag: "Morning Routine"),
                Pair(left: "afraid of",
                     sample: "She is afraid of spiders.",                            tag: "Adjective + Preposition"),
                Pair(left: "aware of",
                     sample: "Were you aware of the new policy?",                   tag: "Adjective + Preposition"),
                Pair(left: "capable of",
                     sample: "He is capable of handling the project alone.",        tag: "Adjective + Preposition"),
                Pair(left: "interested in",
                     sample: "I'm interested in learning more about this.",         tag: "Adjective + Preposition"),
            ],
            collectionId: col2.id
        )
        context.insert(set4)

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
                                  isUserCreated: false, accessTier: setData.accessTier)
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
