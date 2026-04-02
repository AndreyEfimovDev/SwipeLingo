import SwiftUI
import SwiftData

// MARK: - SwipeDirection

enum SwipeDirection { case left, right }

// MARK: - TinderCardsViewModel

@Observable
final class TinderCardsViewModel {

    // MARK: Data

    private(set) var cards: [Card]
    /// Full original card list — used by restart() to restore all active cards.
    private let originalCards: [Card]
    /// setId → display label shown below the word, e.g. "Daily Words · Travel"
    let contextLabels: [UUID: String]
    /// Called when the user taps "Done" on the session completion screen.
    let onDone: (() -> Void)?

    // MARK: Weak cards (rated Forgot or Hard this session)

    private(set) var weakCards: [Card] = []
    var weakCount: Int { weakCards.count }

    // MARK: In-session stats

    /// Cards rated Easy this session (used for "Learnt N" in progress stats row).
    private(set) var learntInSession: Int = 0

    // MARK: UI State

    private(set) var currentIndex: Int = 0
    var dragOffset: CGSize = .zero
    var isFlipped: Bool = false
    /// True while a drag is active OR while the card is still animating back to centre.
    /// Tap-to-flip is blocked when this flag is set.
    var isDragging: Bool = false

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

    /// Cards whose dueDate falls on calendar tomorrow.
    var dueTomorrowCount: Int {
        let cal      = Calendar.current
        let tomorrow = cal.startOfDay(for: .now + 86400)
        let dayAfter = cal.startOfDay(for: .now + 86400 * 2)
        return originalCards.filter { $0.dueDate >= tomorrow && $0.dueDate < dayAfter }.count
    }

    /// Cards whose dueDate falls 2–4 calendar days from now.
    var dueIn3DaysCount: Int {
        let cal      = Calendar.current
        let dayAfter = cal.startOfDay(for: .now + 86400 * 2)
        let in5Days  = cal.startOfDay(for: .now + 86400 * 5)
        return originalCards.filter { $0.dueDate >= dayAfter && $0.dueDate < in5Days }.count
    }

    // MARK: Init

    init(
        cards: [Card],
        contextLabels: [UUID: String] = [:],
        onDone: (() -> Void)? = nil
    ) {
        self.cards = cards
        self.originalCards = cards
        self.contextLabels = contextLabels
        self.onDone = onDone
    }

    // MARK: Actions

    /// Flips front → back.
    func flipToBack() {
        guard !isFlipped else { return }
        isFlipped = true
    }

    /// Toggles flip in both directions. Tap anywhere on the card calls this.
    func flipToggle() {
        isFlipped.toggle()
    }

    /// Called when a drag gesture ends beyond the swipe threshold.
    ///   left  → card stays .active (keep studying)
    ///   right → card becomes .learnt
    func commitSwipe(direction: SwipeDirection, context: ModelContext) {
        guard let card = currentCard else { return }
        if direction == .right {
            card.status = .learnt
            learntInSession += 1
            context.saveWithErrorHandling()
        }
        advance()
    }

    /// Sends the current card to .deleted and advances.
    func commitDelete(context: ModelContext) {
        guard let card = currentCard else { return }
        card.status = .deleted
        context.saveWithErrorHandling()
        advance()
    }

    /// Applies SM-2, records weak cards (Forgot/Hard), saves, and advances.
    func evaluate(rating: SRSRating, context: ModelContext) {
        guard let card = currentCard else { return }
        SRSService().evaluate(card: card, rating: rating)
        if rating == .again || rating == .hard {
            weakCards.append(card)
        }
        if rating == .easy { learntInSession += 1 }
        context.saveWithErrorHandling()
        advance()
    }

    /// Study Again — restarts with all .active original cards. .learnt cards are NOT reset.
    func restart() {
        cards            = originalCards.filter { $0.status == .active }
        weakCards        = []
        learntInSession  = 0
        currentIndex     = 0
        dragOffset       = .zero
        isFlipped        = false
    }

    /// Weak cards — restarts with only cards rated Forgot/Hard this session.
    func restartWeak() {
        let active = weakCards.filter { $0.status == .active }
        if !active.isEmpty { cards = active }
        weakCards        = []
        learntInSession  = 0
        currentIndex     = 0
        dragOffset       = .zero
        isFlipped        = false
    }

    // MARK: Private

    private func advance() {
        currentIndex += 1
        dragOffset = .zero
        isFlipped  = false
    }
}
