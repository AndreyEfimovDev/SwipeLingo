import Foundation
import SwiftData

// MARK: - MockDataSeeder
//
// Seeds one Collection, one CardSet and 8 Cards on first launch.
// Remove or gate behind a flag before App Store submission.

struct MockDataSeeder {

    /// Inserts mock data into `context` if no Cards exist yet.
    /// Safe to call on every launch — the `guard` prevents double-seeding.
    static func seedIfNeeded(into context: ModelContext) {
        // Check for existing data
        let descriptor = FetchDescriptor<Card>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        // MARK: Collection

        let collection = Collection(
            name: "IELTS Vocabulary",
            icon: "book.fill",
            isOwned: true
        )
        context.insert(collection)

        // MARK: CardSet

        let cardSet = CardSet(
            name: "Academic Words",
            collectionId: collection.id
        )
        context.insert(cardSet)

        let sid = cardSet.id

        // MARK: Cards

        let cards: [Card] = [
            Card(
                en: "Serendipity",
                item: "счастливая случайность",
                sampleEN:   ["It was pure serendipity that we met at the airport."],
                sampleItem: ["Наша встреча в аэропорту была чистой случайностью."],
                setId: sid
            ),
            Card(
                en: "Resilience",
                item: "стойкость, жизнестойкость",
                sampleEN:   ["Her resilience in the face of adversity inspired everyone."],
                sampleItem: ["Её стойкость перед лицом невзгод вдохновляла всех."],
                setId: sid
            ),
            Card(
                en: "Ephemeral",
                item: "мимолётный, преходящий",
                sampleEN:   ["Fame can be ephemeral — here today, gone tomorrow."],
                sampleItem: ["Слава бывает мимолётной — сегодня есть, завтра нет."],
                setId: sid
            ),
            Card(
                en: "Eloquent",
                item: "красноречивый",
                sampleEN:   ["She gave an eloquent speech that moved the audience."],
                sampleItem: ["Она произнесла красноречивую речь, тронувшую зал."],
                setId: sid
            ),
            Card(
                en: "Tenacious",
                item: "настойчивый, упорный",
                sampleEN:   ["A tenacious athlete never gives up, no matter the score."],
                sampleItem: ["Упорный спортсмен никогда не сдаётся, каков бы ни был счёт."],
                setId: sid
            ),
            Card(
                en: "Ambiguous",
                item: "неоднозначный, двусмысленный",
                sampleEN:   ["The contract contained several ambiguous clauses."],
                sampleItem: ["В договоре было несколько неоднозначных пунктов."],
                setId: sid
            ),
            Card(
                en: "Paramount",
                item: "первостепенный, важнейший",
                sampleEN:   ["Safety is of paramount importance on a construction site."],
                sampleItem: ["Безопасность имеет первостепенное значение на стройплощадке."],
                setId: sid
            ),
            Card(
                en: "Melancholy",
                item: "меланхолия, грусть",
                sampleEN:   ["A deep melancholy settled over him as autumn arrived."],
                sampleItem: ["С приходом осени им овладела глубокая меланхолия."],
                setId: sid
            ),
        ]

        for card in cards { context.insert(card) }

        // MARK: Inbox (special collection for unsorted cards)

        let inbox = Collection(name: "Inbox", icon: "tray.fill", isOwned: true)
        context.insert(inbox)
        let inboxSet = CardSet(name: "Inbox", collectionId: inbox.id)
        context.insert(inboxSet)

        // MARK: Default active Pile

        let pile = Pile(
            name: "Morning Session",
            setIds: [cardSet.id],
            isActive: true,
            shuffleMethod: .random
        )
        context.insert(pile)

        try? context.save()
    }
}
