import SwiftUI
import SwiftData

// MARK: - SwipeDirection

enum SwipeDirection { case left, right }

// MARK: - TinderCardsViewModel

@Observable
final class TinderCardsViewModel {

    // MARK: Data

    private(set) var cards: [Card]
    /// Полный исходный список карточек — используется в restart() для восстановления всех активных карточек.
    private let originalCards: [Card]
    /// setId → отображаемый лейбл под словом, напр. "Daily Words · Travel"
    let contextLabels: [UUID: String]
    /// Вызывается, когда пользователь тапает "Done" на экране завершения сессии.
    let onDone: (() -> Void)?

    // MARK: Слабые карточки (оценены Forgot или Hard в этой сессии)

    private(set) var weakCards: [Card] = []
    var weakCount: Int { weakCards.count }

    // MARK: Статистика внутри сессии

    /// ID карточек, переведённых в `.learnt` свайпом вправо в этой сессии. Считаются в
    /// `learntInSession`, только пока карточка ДЕЙСТВИТЕЛЬНО остаётся `.learnt` прямо
    /// сейчас (`Card` — `@Model`, общая ссылка для всего приложения) — самокоррекция,
    /// если карточку вернули в Active извне (напр. swipe "Restore" в `CardSetDetailView`,
    /// пока эта же сессия ещё активна): `TinderCardsViewModel` и `CardSetDetailView`
    /// ничего друг о друге не знают, а вот `card.status` — общий факт, доступный обоим.
    private var swipedLearntIDs: Set<UUID> = []
    /// ID карточек, оценённых Easy (SRS) в этой сессии — в отличие от `swipedLearntIDs`,
    /// карточка при этом остаётся `.active` (Easy не меняет `status`, только SRS-поля),
    /// так что внешний Restore на неё в принципе не действует — считаются безусловно.
    private var easyRatedIDs: Set<UUID> = []

    /// Карточки, отмеченные Learnt в этой сессии (свайп вправо + оценённые Easy),
    /// используется для "Learnt N" в строке прогресса.
    var learntInSession: Int {
        let stillLearnt = cards.filter { swipedLearntIDs.contains($0.id) && $0.status == .learnt }.count
        return stillLearnt + easyRatedIDs.count
    }

    // MARK: UI-состояние

    private(set) var currentIndex: Int = 0
    var dragOffset: CGSize = .zero
    var isFlipped: Bool = false
    /// True, пока активен drag ИЛИ пока карточка ещё анимируется обратно к центру.
    /// Тап-для-флипа блокируется, пока установлен этот флаг.
    var isDragging: Bool = false

    // MARK: Derived

    var currentCard: Card? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }

    var isDone: Bool { currentIndex >= cards.count }

    var remaining: Int { max(0, cards.count - currentIndex) }

    /// Угол поворота, управляемый горизонтальным drag (диапазон -1…+1 отображается на ±15°)
    var dragRotation: Angle {
        .degrees(Double(dragOffset.width) / 22.0)
    }

    /// Нормализованный прогресс свайпа: отрицательный = влево (again), положительный = вправо (learnt)
    /// Ограничен диапазоном -1…+1 для интерполяции цвета.
    var swipeProgress: Double {
        min(max(Double(dragOffset.width) / 130.0, -1.0), 1.0)
    }

    var currentContextLabel: String {
        guard let card = currentCard else { return "" }
        return contextLabels[card.setId] ?? ""
    }

    // MARK: Статистика завершения сессии

    /// Карточки, чей dueDate приходится на календарное завтра.
    var dueTomorrowCount: Int {
        let cal      = Calendar.current
        let tomorrow = cal.startOfDay(for: .now + 86400)
        let dayAfter = cal.startOfDay(for: .now + 86400 * 2)
        return originalCards.filter { $0.dueDate >= tomorrow && $0.dueDate < dayAfter }.count
    }

    /// Карточки, чей dueDate приходится на 2–4 календарных дня от сейчас.
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

    // MARK: Действия

    /// Переворачивает лицом → рубашкой.
    func flipToBack() {
        guard !isFlipped else { return }
        isFlipped = true
    }

    /// Переключает флип в обе стороны. Вызывается тапом в любом месте карточки.
    func flipToggle() {
        isFlipped.toggle()
    }

    /// Вызывается, когда drag-жест завершается за порогом свайпа.
    ///   влево  → карточка остаётся .active (продолжаем учить)
    ///   вправо → карточка становится .learnt
    func commitSwipe(direction: SwipeDirection, context: ModelContext) {
        guard let card = currentCard else { return }
        card.isNew = false
        if direction == .right {
            card.status = .learnt
            swipedLearntIDs.insert(card.id)
        }
        context.saveWithErrorHandling()
        advance()
    }

    /// Отправляет текущую карточку в .deleted и переходит к следующей.
    func commitDelete(context: ModelContext) {
        guard let card = currentCard else { return }
        card.isNew = false
        card.status = .deleted
        context.saveWithErrorHandling()
        advance()
    }

    /// Применяет SM-2, записывает слабые карточки (Forgot/Hard), сохраняет и переходит к следующей.
    func evaluate(rating: SRSRating, context: ModelContext) {
        guard let card = currentCard else { return }
        card.isNew = false
        SRSService().evaluate(card: card, rating: rating)
        if rating == .again || rating == .hard {
            weakCards.append(card)
        }
        if rating == .easy { easyRatedIDs.insert(card.id) }
        context.saveWithErrorHandling()
        advance()
    }

    /// Study Again — перезапускает со всеми исходными .active карточками. .learnt карточки НЕ сбрасываются.
    func restart() {
        cards            = originalCards.filter { $0.status == .active }
        weakCards        = []
        swipedLearntIDs  = []
        easyRatedIDs     = []
        currentIndex     = 0
        dragOffset       = .zero
        isFlipped        = false
    }

    /// Weak cards — перезапускает только карточками, оценёнными Forgot/Hard в этой сессии.
    func restartWeak() {
        let active = weakCards.filter { $0.status == .active }
        if !active.isEmpty { cards = active }
        weakCards        = []
        swipedLearntIDs  = []
        easyRatedIDs     = []
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
