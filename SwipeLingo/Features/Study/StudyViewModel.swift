import SwiftUI
import SwiftData

// MARK: - StudyMode

enum StudyMode {
    /// Default — only cards whose dueDate ≤ now.
    case due
    /// "Study anyway" — all active cards regardless of dueDate.
    case all
}

// MARK: - StudyViewModel

@Observable
final class StudyViewModel {

    // MARK: Published state

    private(set) var studyCards: [Card] = []
    private(set) var contextLabels: [UUID: String] = [:]
    /// setId → CEFRLevel — only populated for developer (non-user-created) sets.
    private(set) var cefrLabels: [UUID: CEFRLevel] = [:]
    private(set) var activePileName: String = ""
    /// "Collection › Set1 · Set2 · +N (X cards)" — shown below the card stack.
    private(set) var pileTagsLine: String = ""
    /// Changes on every new session → forces TinderCardsView to reinitialise via .id()
    private(set) var sessionID: UUID = UUID()

    // MARK: Study mode

    private(set) var studyMode: StudyMode = .due
    /// True when in .due mode and no cards are currently due — shows the caught-up screen.
    private(set) var isCaughtUp: Bool = false
    /// "tomorrow · 9 cards" — subtitle on the caught-up screen.
    private(set) var nextReviewLabel: String = ""
    /// Total active cards in the current pile/all — for "Study anyway · All: N" button.
    private(set) var allActiveCount: Int = 0

    var isShowingAddCard = false

    // MARK: Private

    private let pileService = PileService()

    // MARK: Session control

    /// Loads a due-only session if one isn't already running,
    /// or reloads if more due cards appeared since the session started.
    func startSessionIfNeeded(piles: [Pile], allCards: [Card], cardSets: [CardSet], collections: [Collection]) {
        if studyCards.isEmpty {
            load(piles: piles, allCards: allCards, cardSets: cardSets, collections: collections)
            return
        }
        guard studyMode == .due else { return }
        let currentDue = dueCount(piles: piles, allCards: allCards)
        if currentDue > studyCards.count {
            load(piles: piles, allCards: allCards, cardSets: cardSets, collections: collections)
        }
    }

    /// Discards the current session and starts a fresh due-only session.
    func startNewSession(piles: [Pile], allCards: [Card], cardSets: [CardSet], collections: [Collection]) {
        studyMode = .due
        load(piles: piles, allCards: allCards, cardSets: cardSets, collections: collections)
    }

    /// "Study anyway" — loads ALL active cards ignoring dueDate.
    func studyAll(piles: [Pile], allCards: [Card], cardSets: [CardSet], collections: [Collection]) {
        load(piles: piles, allCards: allCards, cardSets: cardSets, collections: collections, dueOnly: false)
    }

    // MARK: Private helpers

    private func load(
        piles: [Pile],
        allCards: [Card],
        cardSets: [CardSet],
        collections: [Collection],
        dueOnly: Bool = true
    ) {
        // Map setId → "Collection › SetName" for per-card breadcrumb display.
        contextLabels = Dictionary(uniqueKeysWithValues: cardSets.map { set in
            let collName = collections.first(where: { $0.id == set.collectionId })?.name
            let label    = collName.map { "\($0) › \(set.name)" } ?? set.name
            return (set.id, label)
        })

        // Map setId → CEFRLevel — developer sets only.
        cefrLabels = Dictionary(uniqueKeysWithValues:
            cardSets.filter { !$0.isUserCreated }.map { ($0.id, $0.cefrLevel) }
        )

        // Resolve active cards and shuffle method for the current pile.
        let activeCards: [Card]
        let shuffleMethod: ShuffleMethod

        if let activePile = piles.first(where: { $0.isActive }) {
            activePileName = activePile.name
            activeCards    = pileService.activeCards(for: activePile, from: allCards)
            shuffleMethod  = activePile.shuffleMethod
            pileTagsLine   = makePileTagsLine(pile: activePile, cardSets: cardSets,
                                              allCards: allCards, collections: collections)
        } else {
            activePileName = "All Cards"
            activeCards    = allCards.filter { $0.status == .active }
            shuffleMethod  = .random
            pileTagsLine   = ""
        }

        allActiveCount = activeCards.count

        if dueOnly {
            let now      = Date.now
            let dueCards = activeCards.filter { $0.dueDate <= now }

            if dueCards.isEmpty {
                studyCards      = []
                studyMode       = .due
                isCaughtUp      = true
                nextReviewLabel = makeNextReviewLabel(from: activeCards)
            } else {
                studyCards      = pileService.apply(shuffleMethod, to: dueCards)
                studyMode       = .due
                isCaughtUp      = false
                nextReviewLabel = ""
            }
        } else {
            studyCards      = pileService.apply(shuffleMethod, to: activeCards)
            studyMode       = .all
            isCaughtUp      = false
            nextReviewLabel = ""
        }

        sessionID = UUID()
    }

    /// Current number of due cards for the active pile (or all cards).
    private func dueCount(piles: [Pile], allCards: [Card]) -> Int {
        let now = Date.now
        if let activePile = piles.first(where: { $0.isActive }) {
            return pileService.activeCards(for: activePile, from: allCards)
                .filter { $0.dueDate <= now }.count
        }
        return allCards.filter { $0.status == .active && $0.dueDate <= now }.count
    }

    /// Builds "tomorrow · 9 cards" or "in 3 days · 4 cards" for the caught-up screen.
    private func makeNextReviewLabel(from cards: [Card]) -> String {
        let upcoming = cards.filter { $0.dueDate > Date.now }
        guard let earliest = upcoming.min(by: { $0.dueDate < $1.dueDate }) else { return "" }

        let cal     = Calendar.current
        let today   = cal.startOfDay(for: .now)
        let dueDay  = cal.startOfDay(for: earliest.dueDate)
        let diff    = cal.dateComponents([.day], from: today, to: dueDay).day ?? 1
        let dayText: String
        switch diff {
        case 0:  dayText = "today"
        case 1:  dayText = "tomorrow"
        default: dayText = "in \(diff) days"
        }
        let count   = upcoming.filter { cal.startOfDay(for: $0.dueDate) == dueDay }.count
        return "\(dayText) · \(count) \(count == 1 ? "card" : "cards")"
    }

    /// Builds "Collection › Set1 · Set2 · +N (X cards)" label shown below the card stack.
    private func makePileTagsLine(pile: Pile, cardSets: [CardSet], allCards: [Card], collections: [Collection]) -> String {
        let sets = cardSets.filter { pile.setIds.contains($0.id) }
        let totalCards = allCards.filter {
            pile.setIds.contains($0.setId) && $0.status == .active
        }.count

        let maxShown = 2
        let names: [String] = sets.map { set in
            if let collection = collections.first(where: { $0.id == set.collectionId }) {
                return "\(collection.name) › \(set.name)"
            }
            return set.name
        }
        var tagParts: [String]
        if names.count <= maxShown {
            tagParts = names
        } else {
            tagParts = Array(names.prefix(maxShown))
            tagParts.append("+\(names.count - maxShown)")
        }

        let tagsString = tagParts.joined(separator: " · ")
        return "\(tagsString) (\(totalCards) \(totalCards == 1 ? "card" : "cards"))"
    }
}
