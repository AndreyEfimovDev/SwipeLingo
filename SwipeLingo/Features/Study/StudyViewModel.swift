import SwiftUI
import SwiftData

// MARK: - StudyViewModel

@Observable
final class StudyViewModel {

    // MARK: Published state

    private(set) var studyCards: [Card] = []
    private(set) var contextLabels: [UUID: String] = [:]
    private(set) var activePileName: String = ""
    /// "Set1 · Set2 · +3 (24 карточки)" — shown below the card stack in StudyView.
    private(set) var pileTagsLine: String = ""
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
            studyCards     = pileService.cards(for: active, from: allCards)
            pileTagsLine   = makePileTagsLine(pile: active, cardSets: cardSets, allCards: allCards)
        } else {
            activePileName = "All Cards"
            studyCards     = allCards.filter { $0.status == .active }.shuffled()
            pileTagsLine   = ""
        }

        sessionID = UUID()
    }

    /// Builds the compact "Set1 · Set2 · +N (X cards)" label.
    private func makePileTagsLine(pile: Pile, cardSets: [CardSet], allCards: [Card]) -> String {
        let sets = cardSets.filter { pile.setIds.contains($0.id) }
        let totalCards = allCards.filter {
            pile.setIds.contains($0.setId) && $0.status == .active
        }.count

        let maxShown = 2
        let names = sets.map { $0.name }
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
