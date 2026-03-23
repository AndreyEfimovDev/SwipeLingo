import SwiftUI
import SwiftData

// MARK: - SwipeDirection

enum SwipeDirection { case left, right }

// MARK: - TinderCardsViewModel

@Observable
final class TinderCardsViewModel {

    // MARK: Data

    let cards: [Card]
    /// setId → display label shown below the word, e.g. "Daily Words · Travel"
    let contextLabels: [UUID: String]

    // MARK: UI State

    private(set) var currentIndex: Int = 0
    var dragOffset: CGSize = .zero
    var isFlipped: Bool = false

    // MARK: Derived

    var currentCard: Card? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }

    var isDone: Bool { currentIndex >= cards.count }

    var remaining: Int { max(0, cards.count - currentIndex) }

    /// Rotation angle driven by horizontal drag (-1…+1 range mapped to ±15°)
    var dragRotation: Angle {
        .degrees(Double(dragOffset.width) / 22.0)
    }

    /// Normalised swipe progress: negative = left (again), positive = right (learnt)
    /// Clamped to -1…+1 for colour interpolation.
    var swipeProgress: Double {
        min(max(Double(dragOffset.width) / 130.0, -1.0), 1.0)
    }

    var currentContextLabel: String {
        guard let card = currentCard else { return "" }
        return contextLabels[card.setId] ?? ""
    }

    // MARK: Init

    init(cards: [Card], contextLabels: [UUID: String] = [:]) {
        self.cards = cards
        self.contextLabels = contextLabels
    }

    // MARK: Actions

    /// Toggles the card face (front ↔ back).
    func flip() {
        isFlipped.toggle()
    }

    /// Called when a drag gesture ends beyond the swipe threshold.
    ///   left  → card stays .active (keep studying)
    ///   right → card becomes .learnt
    func commitSwipe(direction: SwipeDirection, context: ModelContext) {
        guard let card = currentCard else { return }
        if direction == .right {
            card.status = .learnt
            try? context.save()
        }
        advance()
    }

    /// Applies SM-2, saves, and advances to the next card.
    func evaluate(rating: SRSRating, context: ModelContext) {
        guard let card = currentCard else { return }
        SRSService().evaluate(card: card, rating: rating)
        try? context.save()
        advance()
    }

    // MARK: Private

    private func advance() {
        currentIndex += 1
        dragOffset = .zero
        isFlipped  = false
    }
}
