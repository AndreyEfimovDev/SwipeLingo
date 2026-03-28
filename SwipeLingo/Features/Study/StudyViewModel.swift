import SwiftUI
import SwiftData

// MARK: - StudyViewModel

@Observable
final class StudyViewModel {

    // MARK: Published state

    private(set) var studyCards: [Card] = []
    private(set) var contextLabels: [UUID: String] = [:]
    /// setId → CEFRLevel — only populated for developer (non-user-created) sets.
    private(set) var cefrLabels: [UUID: CEFRLevel] = [:]
    private(set) var activePileName: String = ""
    /// "Collection › Set1 · Set2 · +N (X cards)" — shown below the card stack in StudyView.
    private(set) var pileTagsLine: String = ""
    /// Changes on every new session → forces TinderCardsView to reinitialise via .id()
    private(set) var sessionID: UUID = UUID()

    var isShowingAddCard = false

    // MARK: Private

    private let pileService = PileService()

    // MARK: Session control

    /// Loads a session only if one isn't already running,
    /// OR if more active cards are available than when the session was loaded.
    func startSessionIfNeeded(piles: [Pile], allCards: [Card], cardSets: [CardSet], collections: [Collection]) {
        if studyCards.isEmpty {
            load(piles: piles, allCards: allCards, cardSets: cardSets, collections: collections)
            return
        }
        // Reload if new cards have been activated since the session started
        let currentCount: Int
        if let active = piles.first(where: { $0.isActive }) {
            currentCount = allCards.filter { active.setIds.contains($0.setId) && $0.status == .active }.count
        } else {
            currentCount = allCards.filter { $0.status == .active }.count
        }
        if currentCount > studyCards.count {
            load(piles: piles, allCards: allCards, cardSets: cardSets, collections: collections)
        }
    }

    /// Discards the current session and starts a fresh one.
    func startNewSession(piles: [Pile], allCards: [Card], cardSets: [CardSet], collections: [Collection]) {
        load(piles: piles, allCards: allCards, cardSets: cardSets, collections: collections)
    }

    // MARK: Private helpers

    private func load(piles: [Pile], allCards: [Card], cardSets: [CardSet], collections: [Collection]) {
        // Map setId → "Collection › SetName" for per-card breadcrumb display.
        contextLabels = Dictionary(uniqueKeysWithValues: cardSets.map { set in
            let collName = collections.first(where: { $0.id == set.collectionId })?.name
            let label    = collName.map { "\($0) › \(set.name)" } ?? set.name
            return (set.id, label)
        })

        // Map setId → CEFRLevel — developer sets only (user-created sets don't show level).
        cefrLabels = Dictionary(uniqueKeysWithValues:
            cardSets.filter { !$0.isUserCreated }.map { ($0.id, $0.cefrLevel) }
        )

        if let active = piles.first(where: { $0.isActive }) {
            activePileName = active.name
            studyCards     = pileService.cards(for: active, from: allCards)
            pileTagsLine   = makePileTagsLine(pile: active, cardSets: cardSets, allCards: allCards, collections: collections)
        } else {
            activePileName = "All Cards"
            studyCards     = allCards.filter { $0.status == .active }.shuffled()
            pileTagsLine   = ""
        }

        sessionID = UUID()
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
