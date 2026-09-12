import Foundation
import SwiftData

// MARK: - PileLike
//
// Общая форма Pile (Cards) и PairsPile (Pairs) — оба представляют собой именованную
// подборку setId'шников, из которых только один может быть активным одновременно.
// Позволяет PileManagementService мутировать оба типа одной реализацией вместо
// двух почти идентичных копий.

protocol PileLike: AnyObject {
    var setIds: [UUID] { get set }
    var isActive: Bool { get set }
}

extension Pile: PileLike {}
extension PairsPile: PileLike {}

// MARK: - PileManagementService
//
// Общие мутации Pile, используемые и в Cards Library (LibraryView),
// и в Pairs Library (PairsLibraryView). Раньше эта логика была продублирована независимо
// в обоих View — теперь это единственный источник истины для неё.
//
// Сервис без состояния: ModelContext передаётся параметром на каждый вызов, а не
// хранится внутри — так же, как уже сделано с ImportFSService().syncFromFirestore(into: context, ...).

struct PileManagementService {

    /// Добавляет `setId` в `pile.setIds`, если его там нет, или убирает, если уже есть.
    func toggleSet<P: PileLike>(_ setId: UUID, in pile: P, context: ModelContext) {
        if pile.setIds.contains(setId) {
            pile.setIds.removeAll { $0 == setId }
        } else {
            pile.setIds.append(setId)
        }
        context.saveWithErrorHandling()
    }

    /// Деактивирует все пайлы из `all`, затем активирует `pile` — активным может быть
    /// только один пайл одновременно.
    func activate<P: PileLike>(_ pile: P, among all: [P], context: ModelContext) {
        for p in all { p.isActive = false }
        pile.isActive = true
        context.saveWithErrorHandling()
    }

    /// Создаёт новый Cards `Pile`, сразу добавляя в него один сет.
    /// Ничего не делает (возвращает `false`), если `name` пустое после trim.
    @discardableResult
    func createCardsPile(named name: String, setId: UUID, context: ModelContext) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        context.insert(Pile(name: trimmed, setIds: [setId]))
        context.saveWithErrorHandling()
        return true
    }

    /// Создаёт новый Pairs `PairsPile`, сразу добавляя в него один сет.
    /// Ничего не делает (возвращает `false`), если `name` пустое после trim.
    @discardableResult
    func createPairsPile(named name: String, setId: UUID, context: ModelContext) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        context.insert(PairsPile(name: trimmed, setIds: [setId]))
        context.saveWithErrorHandling()
        return true
    }

    /// Удаляет Pile (Cards или Pairs) целиком — у пайлов нет собственного каскадного
    /// контента, они только ссылаются на setId'шники.
    func delete<P: PersistentModel>(_ pile: P, context: ModelContext) {
        context.delete(pile)
        context.saveWithErrorHandling()
    }
}
