import SwiftUI
import SwiftData

// MARK: - LibraryViewModel
//
// Бизнес-логика LibraryView: фильтрация коллекций/сетов, членство в Pile, синхронизация
// и каскадные удаления. Результаты @Query остаются во View и передаются в эти методы
// параметрами (та же конвенция, что и в FlashCardsViewModel) — сам ViewModel хранит
// только isSyncing, единственное состояние, реально привязанное к выполняющемуся
// действию, а не к SwiftData.

@Observable
final class LibraryViewModel {

    private(set) var isSyncing = false

    private let pileService = PileManagementService()

    // MARK: - Счётчики

    /// Количество сетов, принадлежащих `collection`.
    func setCount(for collection: Collection, cardSets: [CardSet]) -> Int {
        cardSets.filter { $0.collectionId == collection.id }.count
    }

    /// Количество неудалённых карточек по всем сетам в `collection`.
    func cardCount(for collection: Collection, cardSets: [CardSet], allCards: [Card]) -> Int {
        let setIds = Set(cardSets.filter { $0.collectionId == collection.id }.map(\.id))
        return allCards.filter { setIds.contains($0.setId) && $0.status != .deleted }.count
    }

    /// Количество неудалённых карточек в `cardSet`.
    func cardCount(forSet cardSet: CardSet, allCards: [Card]) -> Int {
        allCards.filter { $0.setId == cardSet.id && $0.status != .deleted }.count
    }

    /// Количество карточек в `cardSet`, импортированных с момента, когда пользователь
    /// последний раз открывал этот сет.
    func newCount(forSet cardSet: CardSet, allCards: [Card]) -> Int {
        allCards.filter { $0.setId == cardSet.id && $0.isNew }.count
    }

    /// Карточки, сейчас находящиеся в корзине Deleted Cards.
    func deletedCardsCount(allCards: [Card]) -> Int {
        allCards.filter { $0.status == .deleted }.count
    }

    /// Активные карточки, принадлежащие сетам из `pile`.
    func activeCardCount(for pile: Pile, allCards: [Card]) -> Int {
        allCards.filter { pile.setIds.contains($0.setId) && $0.status == .active }.count
    }

    // MARK: - Фильтрация коллекций / сетов

    /// Сеты, видимые в `collection`: в пределах уровня CEFR пользователя, не
    /// soft-deleted, и либо пустые (только что созданы), либо всё ещё содержат хотя бы
    /// одну неудалённую карточку.
    func setsForCollection(
        _ collection: Collection, cardSets: [CardSet], allCards: [Card], userLevel: CEFRLevel
    ) -> [CardSet] {
        cardSets
            .filter { $0.collectionId == collection.id && $0.cefrLevel <= userLevel && !$0.isSoftDeleted }
            .filter { set in
                let cards = allCards.filter { $0.setId == set.id }
                return cards.isEmpty || cards.contains { $0.status != .deleted }
            }
    }

    /// Inbox + My Sets + остальные пользовательские коллекции с видимым контентом, в этом порядке.
    func myCollections(from collections: [Collection], cardSets: [CardSet], allCards: [Card]) -> [Collection] {
        let inbox    = collections.filter { $0.name == "Inbox" }
        let mySets   = collections.filter { $0.name == "My Sets" }
        let userRest = collections.filter {
            $0.isUserCreated && $0.name != "Inbox" && $0.name != "My Sets"
                && hasVisibleContent($0, cardSets: cardSets, allCards: allCards)
        }
        return inbox + mySets + userRest
    }

    /// Облачные (Firestore) коллекции — только те, у которых есть хотя бы один сет для
    /// уровня пользователя. Пустые скрываем: они могут кратковременно появляться во время
    /// sync пока cleanup ещё не удалил их, либо если у пользователя нет контента на его
    /// текущем уровне CEFR.
    func curatedCollections(
        from collections: [Collection], cardSets: [CardSet], allCards: [Card], userLevel: CEFRLevel
    ) -> [Collection] {
        collections.filter {
            !$0.isUserCreated && !setsForCollection($0, cardSets: cardSets, allCards: allCards, userLevel: userLevel).isEmpty
        }
    }

    /// Коллекция видима, если у неё ещё нет сетов (только что создана), либо хотя бы
    /// один сет пустой, либо хотя бы один сет имеет хотя бы одну неудалённую карточку.
    func hasVisibleContent(_ collection: Collection, cardSets: [CardSet], allCards: [Card]) -> Bool {
        let setsInCollection = cardSets.filter { $0.collectionId == collection.id }
        if setsInCollection.isEmpty { return true }
        return setsInCollection.contains { set in
            let cards = allCards.filter { $0.setId == set.id }
            return cards.isEmpty || cards.contains { $0.status != .deleted }
        }
    }

    // MARK: - Синхронизация

    /// Ручной sync = full sync: перекачивает весь контент до уровня пользователя заново
    /// и запускает orphan removal, гарантируя, что локальные данные совпадают с Firestore.
    /// `nativeLangRaw` — сырое значение из `@AppStorage`; если оно не распознано, используем `.russian`.
    func syncContent(context: ModelContext, nativeLangRaw: String, level: CEFRLevel) async {
        isSyncing = true
        defer { isSyncing = false }
        let language = NativeLanguage(rawValue: nativeLangRaw) ?? .russian
        await ImportFSService().syncFromFirestore(
            into: context, language: language, upToLevel: level, forceFullSync: true
        )
    }

    // MARK: - Членство в Pile

    func toggleSet(_ set: CardSet, in pile: Pile, context: ModelContext) {
        pileService.toggleSet(set.id, in: pile, context: context)
    }

    /// Создаёт новый Pile с одним сетом `set`. Возвращает `true`, если пайл был создан
    /// (имя не оказалось пустым) — вызывающая сторона использует это, чтобы раскрыть
    /// список пайлов и показать новый.
    @discardableResult
    func createNewPile(named name: String, with set: CardSet, context: ModelContext) -> Bool {
        pileService.createCardsPile(named: name, setId: set.id, context: context)
    }

    func activatePile(_ pile: Pile, among allPiles: [Pile], context: ModelContext) {
        pileService.activate(pile, among: allPiles, context: context)
    }

    func deletePile(_ pile: Pile, context: ModelContext) {
        pileService.delete(pile, context: context)
    }

    // MARK: - Каскадные удаления

    /// Удаляет `cardSet` вместе с его карточками.
    /// - Пользовательский: hard-delete сета, если карточек нет, иначе soft-delete карточек.
    /// - Облачный: tombstone сета (`isSoftDeleted = true`), чтобы sync его не перекачал
    ///   заново, плюс soft-delete карточек — они появляются в Deleted Cards с кнопкой Restore.
    func deleteSetWithCards(_ cardSet: CardSet, allCards: [Card], context: ModelContext) {
        let cards = allCards.filter { $0.setId == cardSet.id }
        if cardSet.isUserCreated {
            if cards.isEmpty {
                context.delete(cardSet)
            } else {
                cards.forEach { $0.status = .deleted }
            }
        } else {
            cardSet.isSoftDeleted = true
            cards.forEach { $0.status = .deleted }
        }
        context.saveWithErrorHandling()
    }

    /// Удаляет `collection` вместе со всеми сетами и карточками внутри неё. Пустые сеты
    /// удаляются сразу; сеты с карточками soft-deleted (карточки → `.deleted`), а сама
    /// коллекция остаётся — она исчезнет, когда опустеет последний её сет.
    func deleteCollectionWithCards(_ collection: Collection, cardSets: [CardSet], allCards: [Card], context: ModelContext) {
        let setsInCollection = cardSets.filter { $0.collectionId == collection.id }
        var hasSoftDeletedCards = false

        for set in setsInCollection {
            let cards = allCards.filter { $0.setId == set.id }
            if cards.isEmpty {
                context.delete(set)
            } else {
                hasSoftDeletedCards = true
                cards.forEach { $0.status = .deleted }
            }
        }

        if !hasSoftDeletedCards {
            context.delete(collection)
        }
        context.saveWithErrorHandling()
    }
}
