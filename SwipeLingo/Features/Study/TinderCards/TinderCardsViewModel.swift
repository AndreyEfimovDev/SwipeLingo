import SwiftUI
import SwiftData

// MARK: - SwipeDirection

enum SwipeDirection { case left, right }

// MARK: - TinderCardsViewModel

@Observable
final class TinderCardsViewModel {

    // MARK: Data

    private(set) var cards: [Card]
    /// setId → display label shown below the word, e.g. "Daily Words · Travel"
    let contextLabels: [UUID: String]
    /// Called when the user taps "Done" on the session completion screen.
    let onDone: (() -> Void)?

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

    // MARK: Session completion stats

    /// Cards whose dueDate falls in the next 24–48 h window ("tomorrow").
    var dueTomorrowCount: Int {
        let now   = Date.now
        let start = now.addingTimeInterval(86400 * 1)
        let end   = now.addingTimeInterval(86400 * 2)
        return cards.filter { $0.dueDate >= start && $0.dueDate < end }.count
    }

    /// Cards whose dueDate falls in the 2–5 day window ("in 3 days").
    var dueIn3DaysCount: Int {
        let now   = Date.now
        let start = now.addingTimeInterval(86400 * 2)
        let end   = now.addingTimeInterval(86400 * 5)
        return cards.filter { $0.dueDate >= start && $0.dueDate < end }.count
    }

    // MARK: Init

    init(cards: [Card], contextLabels: [UUID: String] = [:], onDone: (() -> Void)? = nil) {
        self.cards = cards
        self.contextLabels = contextLabels
        self.onDone = onDone
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

    /// Restarts the session from the first card (all original cards).
    func restart() {
        currentIndex = 0
        dragOffset   = .zero
        isFlipped    = false
    }

    /// Restarts with only cards whose dueDate is within the next 24 h (due today).
    func restartDue() {
        let dueCards = cards.filter { $0.dueDate < Date.now.addingTimeInterval(86400) }
        if !dueCards.isEmpty { cards = dueCards }
        currentIndex = 0
        dragOffset   = .zero
        isFlipped    = false
    }

    // MARK: Private

    private func advance() {
        currentIndex += 1
        dragOffset = .zero
        isFlipped  = false
    }
}
