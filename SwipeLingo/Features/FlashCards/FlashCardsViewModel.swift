import SwiftUI
import SwiftData

// MARK: - StudyMode

enum StudyMode {
    /// Only cards whose dueDate ≤ now (active after studyStartHour).
    case due
    /// All active cards regardless of dueDate.
    case all
}

// MARK: - FlashCardsViewModel

@Observable
final class FlashCardsViewModel {

    // MARK: Published state

    private(set) var studyCards: [Card] = []
    private(set) var contextLabels: [UUID: String] = [:]
    private(set) var cefrLabels: [UUID: CEFRLevel] = [:]
    private(set) var activePileName: String = ""
    private(set) var pileTagsLine: String = ""
    /// Changes on every new session → forces TinderCardsView to reinitialise via .id()
    private(set) var sessionID: UUID = UUID()

    // MARK: Study mode

    private(set) var studyMode: StudyMode = .all
    /// True only when the user has completed an All-mode session (truly done for today).
    private(set) var isCaughtUp: Bool = false
    /// "tomorrow · 9 cards" — subtitle on the caught-up screen.
    private(set) var nextReviewLabel: String = ""
    /// Total active cards in the current pile — shown as left stat in progress row.
    private(set) var allActiveCount: Int = 0
    /// Cards already in .learnt status in the current pile at session start.
    private(set) var pileLearntCount: Int = 0

    var isShowingAddCard = false

    // MARK: Private

    private let pileService = PileService()

    // MARK: Session control

    /// Loads a session if one isn't already running.
    func startSessionIfNeeded(
        piles: [Pile], allCards: [Card], cardSets: [CardSet],
        collections: [Collection], dueHour: Int
    ) {
        guard studyCards.isEmpty && !isCaughtUp else { return }
        load(piles: piles, allCards: allCards, cardSets: cardSets,
             collections: collections, dueHour: dueHour)
    }

    /// Discards the current session and starts a fresh session (respects dueHour).
    func startNewSession(
        piles: [Pile], allCards: [Card], cardSets: [CardSet],
        collections: [Collection], dueHour: Int
    ) {
        isCaughtUp = false
        load(piles: piles, allCards: allCards, cardSets: cardSets,
             collections: collections, dueHour: dueHour)
    }

    /// "Study anyway" — loads ALL active cards ignoring dueDate and hour threshold.
    func studyAll(
        piles: [Pile], allCards: [Card], cardSets: [CardSet],
        collections: [Collection]
    ) {
        isCaughtUp = false
        load(piles: piles, allCards: allCards, cardSets: cardSets,
             collections: collections, dueHour: 0, dueOnly: false)
    }

    /// Called by TinderCardsView when all session cards are swiped/rated.
    /// - Due mode done → auto-switch to All mode.
    /// - All mode done → show caught-up screen.
    func onSessionComplete(
        piles: [Pile], allCards: [Card], cardSets: [CardSet],
        collections: [Collection], dueHour: Int
    ) {
        switch studyMode {
        case .due:
            // Due session finished → continue with all active cards
            load(piles: piles, allCards: allCards, cardSets: cardSets,
                 collections: collections, dueHour: dueHour, dueOnly: false)
        case .all:
            // All-mode session finished → user is truly caught up for today
            let pileCards: [Card]
            if let pile = piles.first(where: { $0.isActive }) {
                pileCards = pileService.activeCards(for: pile, from: allCards)
            } else {
                pileCards = allCards.filter { $0.status == .active }
            }
            studyCards      = []
            isCaughtUp      = true
            nextReviewLabel = makeNextReviewLabel(from: pileCards)
            sessionID       = UUID()
        }
    }

    // MARK: Private helpers

    private func load(
        piles: [Pile],
        allCards: [Card],
        cardSets: [CardSet],
        collections: [Collection],
        dueHour: Int,
        dueOnly: Bool = true
    ) {
        // Context labels: setId → "Collection › SetName"
        contextLabels = Dictionary(uniqueKeysWithValues: cardSets.map { set in
            let collName = collections.first(where: { $0.id == set.collectionId })?.name
            let label    = collName.map { "\($0) › \(set.name)" } ?? set.name
            return (set.id, label)
        })
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

        allActiveCount  = activeCards.count
        pileLearntCount = {
            if let pile = piles.first(where: { $0.isActive }) {
                let setIds = Set(pile.setIds)
                return allCards.filter { setIds.contains($0.setId) && $0.status == .learnt }.count
            }
            return allCards.filter { $0.status == .learnt }.count
        }()

        if dueOnly {
            let now  = Date.now
            let hour = Calendar.current.component(.hour, from: now)

            // Only offer Due mode after the configured start hour
            if hour >= dueHour {
                let dueCards = activeCards.filter { $0.dueDate <= now }
                if !dueCards.isEmpty {
                    // Due cards available → Due mode
                    studyCards = pileService.apply(shuffleMethod, to: dueCards)
                    studyMode  = .due
                    sessionID  = UUID()
                    return
                }
            }
            // Before start hour OR no due cards → All mode directly (no caught-up screen)
        }

        // All mode
        studyCards = pileService.apply(shuffleMethod, to: activeCards)
        studyMode  = .all
        sessionID  = UUID()
    }

    // MARK: - Labels

    /// "tomorrow · 9 cards" or "in 3 days · 4 cards" for the caught-up screen.
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
        let count = upcoming.filter { cal.startOfDay(for: $0.dueDate) == dueDay }.count
        return "\(dayText) · \(count) \(count == 1 ? "card" : "cards")"
    }

    /// "Collection › Set1 · Set2 · +N (X cards)" below the card stack.
    private func makePileTagsLine(pile: Pile, cardSets: [CardSet],
                                  allCards: [Card], collections: [Collection]) -> String {
        let sets       = cardSets.filter { pile.setIds.contains($0.id) }
        let totalCards = allCards.filter {
            pile.setIds.contains($0.setId) && $0.status == .active
        }.count
        let maxShown   = 2
        let names: [String] = sets.map { set in
            if let col = collections.first(where: { $0.id == set.collectionId }) {
                return "\(col.name) › \(set.name)"
            }
            return set.name
        }
        var parts = names.count <= maxShown ? names : Array(names.prefix(maxShown)) + ["+\(names.count - maxShown)"]
        _ = parts  // suppress unused warning
        let tagStr = (names.count <= maxShown ? names : Array(names.prefix(maxShown)) + ["+\(names.count - maxShown)"])
            .joined(separator: " · ")
        return "\(tagStr) (\(totalCards) \(totalCards == 1 ? "card" : "cards"))"
    }
}
