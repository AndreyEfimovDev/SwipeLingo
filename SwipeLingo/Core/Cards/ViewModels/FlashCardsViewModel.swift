import SwiftUI
import SwiftData

// MARK: - StudyMode

enum StudyMode {
    /// Только карточки, у которых dueDate ≤ сейчас (активны после studyStartHour).
    case due
    /// Все активные карточки независимо от dueDate.
    case all
}

// MARK: - FlashCardsViewModel

@Observable
final class FlashCardsViewModel {

    // MARK: Published state

    private(set) var studyCards: [Card] = []
    /// ID карточек, показывающих заблокированную обратную сторону (превышен лимит paywall-превью).
    private(set) var lockedCardIds: Set<UUID> = []
    private(set) var contextLabels: [UUID: String] = [:]
    private(set) var cefrLabels: [UUID: CEFRLevel] = [:]
    private(set) var activePileName: String = ""
    private(set) var pileTagsLine: String = ""
    /// Меняется на каждую новую сессию → заставляет TinderCardsView переинициализироваться через .id()
    private(set) var sessionID: UUID = UUID()

    // MARK: Study mode

    private(set) var studyMode: StudyMode = .all
    /// True, только когда пользователь завершил сессию в режиме All (действительно закончил на сегодня).
    private(set) var isCaughtUp: Bool = false
    /// "tomorrow · 9 cards" — подзаголовок на экране "всё пройдено".
    private(set) var nextReviewLabel: String = ""
    /// Всего активных карточек в текущем pile — показывается как левая статистика в строке прогресса.
    private(set) var allActiveCount: Int = 0
    /// Карточки, уже находящиеся в статусе .learnt в текущем pile на старте сессии.
    private(set) var pileLearntCount: Int = 0

    // MARK: Private

    private let pileService = PileService()

    // MARK: Session control

    /// Загружает сессию, если она ещё не запущена.
    func startSessionIfNeeded(
        piles: [Pile], allCards: [Card], cardSets: [CardSet],
        collections: [Collection], dueHour: Int, srsEnabled: Bool = true,
        userPlan: AccessTier = .free
    ) {
        guard studyCards.isEmpty && !isCaughtUp else { return }
        load(piles: piles, allCards: allCards, cardSets: cardSets,
             collections: collections, dueHour: dueHour, dueOnly: srsEnabled,
             userPlan: userPlan)
    }

    /// Отбрасывает текущую сессию и запускает новую (учитывает dueHour).
    func startNewSession(
        piles: [Pile], allCards: [Card], cardSets: [CardSet],
        collections: [Collection], dueHour: Int, srsEnabled: Bool = true,
        userPlan: AccessTier = .free
    ) {
        isCaughtUp = false
        load(piles: piles, allCards: allCards, cardSets: cardSets,
             collections: collections, dueHour: dueHour, dueOnly: srsEnabled,
             userPlan: userPlan)
    }

    /// Переключает отображение в режим Due без перезагрузки карточек и сброса sessionID.
    /// Используется, когда пользователь тапает переключатель Due, но due-карточек нет —
    /// показывает оверлей "всё пройдено", не сбивая текущую позицию карточки.
    func switchToDueDisplay() {
        studyMode = .due
    }

    /// "Study anyway" — загружает ВСЕ активные карточки, игнорируя dueDate и часовой порог.
    func studyAll(
        piles: [Pile], allCards: [Card], cardSets: [CardSet],
        collections: [Collection], userPlan: AccessTier = .free
    ) {
        isCaughtUp = false
        load(piles: piles, allCards: allCards, cardSets: cardSets,
             collections: collections, dueHour: 0, dueOnly: false,
             userPlan: userPlan)
    }

    /// Вызывается TinderCardsView, когда все карточки сессии просвайпаны/оценены.
    /// - Режим Due завершён → автопереключение на режим All.
    /// - Режим All завершён → показать экран "всё пройдено".
    func onSessionComplete(
        piles: [Pile], allCards: [Card], cardSets: [CardSet],
        collections: [Collection], dueHour: Int
    ) {
        switch studyMode {
        case .due:
            // Сессия Due завершена → продолжаем всеми активными карточками
            load(piles: piles, allCards: allCards, cardSets: cardSets,
                 collections: collections, dueHour: dueHour, dueOnly: false)
        case .all:
            // Сессия All завершена → пользователь действительно закончил на сегодня
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
        dueOnly: Bool = true,
        userPlan: AccessTier = .free
    ) {
        // Контекстные лейблы: setId → "Collection › SetName"
        contextLabels = Dictionary(uniqueKeysWithValues: cardSets.map { set in
            let collName = collections.first(where: { $0.id == set.collectionId })?.name
            let label    = collName.map { "\($0) › \(set.name)" } ?? set.name
            return (set.id, label)
        })
        cefrLabels = Dictionary(uniqueKeysWithValues:
            cardSets.filter { !$0.isUserCreated }.map { ($0.id, $0.cefrLevel) }
        )

        // cardSets — уже отфильтрованы по уровню пользователя (levelFilteredCardSets из View).
        // Ограничиваем activeCards только карточками из этих сетов — иначе при понижении уровня
        // в сессию попадали бы карточки выше текущего уровня пользователя.
        let allowedSetIds = Set(cardSets.map(\.id))

        // Определяем активные карточки и метод перемешивания для текущего pile.
        let activeCards: [Card]
        let shuffleMethod: ShuffleMethod

        if let activePile = piles.first(where: { $0.isActive }) {
            activePileName = activePile.name
            let pileCards  = pileService.activeCards(for: activePile, from: allCards)
            activeCards    = pileCards.filter { allowedSetIds.contains($0.setId) }
            shuffleMethod  = activePile.shuffleMethod
            pileTagsLine   = makePileTagsLine(pile: activePile, cardSets: cardSets,
                                              allCards: allCards, collections: collections)
        } else {
            activePileName = "All Cards"
            activeCards    = allCards.filter { $0.status == .active && allowedSetIds.contains($0.setId) }
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

            // Предлагаем режим Due только после настроенного стартового часа
            if hour >= dueHour {
                let dueCards = activeCards.filter { $0.dueDate <= now }
                if !dueCards.isEmpty {
                    // Есть due-карточки → режим Due
                    studyCards = pileService.apply(shuffleMethod, to: dueCards)
                    studyMode  = .due
                    sessionID  = UUID()
                    computeLockedCards(cardSets: cardSets, userPlan: userPlan)
                    return
                }
            }
            // До стартового часа ИЛИ нет due-карточек → сразу режим All (без экрана "всё пройдено")
        }

        // Режим All
        studyCards = pileService.apply(shuffleMethod, to: activeCards)
        studyMode  = .all
        sessionID  = UUID()
        computeLockedCards(cardSets: cardSets, userPlan: userPlan)
    }

    private func computeLockedCards(cardSets: [CardSet], userPlan: AccessTier) {
        let setIndex = Dictionary(uniqueKeysWithValues: cardSets.map { ($0.id, $0) })
        var paidSeen = 0
        var locked   = Set<UUID>()
        for card in studyCards {
            guard let set = setIndex[card.setId],
                  !userPlan.canAccess(set.accessTier) else { continue }
            paidSeen += 1
            if paidSeen > Constants.paywallPreviewLimit { locked.insert(card.id) }
        }
        lockedCardIds = locked
    }

    // MARK: - Labels

    /// "tomorrow · 9 cards" или "in 3 days · 4 cards" для экрана "всё пройдено".
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

    /// "Collection › Set1 · Set2 · +N (X cards)" под стопкой карточек.
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
        let tagStr = (names.count <= maxShown ? names : Array(names.prefix(maxShown)) + ["+\(names.count - maxShown)"])
            .joined(separator: " · ")
        return "\(tagStr) (\(totalCards) \(totalCards == 1 ? "card" : "cards"))"
    }
}
