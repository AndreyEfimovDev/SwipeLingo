import SwiftUI
import SwiftData

// MARK: - StudyViewModel

@Observable
final class StudyViewModel {

    // MARK: Published state

    private(set) var studyCards: [Card] = []
    private(set) var contextLabels: [UUID: String] = [:]
    private(set) var activePileName: String = ""
    /// Changes on every new session → forces TinderCardsView to reinitialise via .id()
    private(set) var sessionID: UUID = UUID()

    var isShowingAddCard = false

    // MARK: Private

    private let pileService = PileService()

    // MARK: Session control

    /// Loads a session only if one isn't already running.
    func startSessionIfNeeded(piles: [Pile], allCards: [Card], cardSets: [CardSet]) {
        guard studyCards.isEmpty else { return }
        load(piles: piles, allCards: allCards, cardSets: cardSets)
    }

    /// Discards the current session and starts a fresh one.
    func startNewSession(piles: [Pile], allCards: [Card], cardSets: [CardSet]) {
        load(piles: piles, allCards: allCards, cardSets: cardSets)
    }

    // MARK: Private helpers

    private func load(piles: [Pile], allCards: [Card], cardSets: [CardSet]) {
        contextLabels = Dictionary(uniqueKeysWithValues: cardSets.map { ($0.id, $0.name) })

        if let active = piles.first(where: { $0.isActive }) {
            activePileName = active.name
            studyCards = pileService.cards(for: active, from: allCards)
        } else {
            activePileName = "Все карточки"
            studyCards = allCards.filter { $0.status == .active }.shuffled()
        }

        sessionID = UUID()
    }
}
