import SwiftUI
import SwiftData

// MARK: - PairsPileBuilderViewModel

@Observable
final class PairsPileBuilderViewModel {

    var name: String
    /// Выбранные сеты В ПОРЯДКЕ ВЫБОРА (не `Set`): этот порядок сохраняется в `PairsPile.setIds` и
    /// задаёт показ при `.sequential`. У `Set` порядка нет — раньше `Array(Set)` давал произвольный.
    var selectedSetIds: [UUID]
    var shuffleMethod: ShuffleMethod

    let editingPile: PairsPile?

    private let initialName: String
    private let initialSetIds: [UUID]
    private let initialShuffleMethod: ShuffleMethod

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedSetIds.isEmpty
    }

    var hasChanges: Bool {
        guard editingPile != nil else { return true }
        return name != initialName
            || selectedSetIds != initialSetIds   // сравнение с учётом порядка: он влияет на показ
            || shuffleMethod != initialShuffleMethod
    }

    var canSave: Bool { isValid && hasChanges }

    init(editingPile: PairsPile? = nil) {
        self.editingPile          = editingPile
        self.name                 = editingPile?.name          ?? ""
        self.selectedSetIds       = editingPile?.setIds        ?? []
        self.shuffleMethod        = editingPile?.shuffleMethod ?? .random
        self.initialName          = editingPile?.name          ?? ""
        self.initialSetIds        = editingPile?.setIds        ?? []
        self.initialShuffleMethod = editingPile?.shuffleMethod ?? .random
    }

    /// Добавляет сет в конец выбора либо убирает его; порядок остальных сетов не меняется.
    func toggleSet(_ id: UUID) {
        if let index = selectedSetIds.firstIndex(of: id) {
            selectedSetIds.remove(at: index)
        } else {
            selectedSetIds.append(id)
        }
    }

    @discardableResult
    func save(context: ModelContext) -> PairsPile {
        if let pile = editingPile {
            pile.name          = name.trimmingCharacters(in: .whitespaces)
            pile.setIds        = selectedSetIds
            pile.shuffleMethod = shuffleMethod
            pile.updatedAt     = .now
            context.saveWithErrorHandling()
            return pile
        } else {
            let pile = PairsPile(
                name: name.trimmingCharacters(in: .whitespaces),
                setIds: selectedSetIds,
                shuffleMethod: shuffleMethod,
                isActive: false
            )
            context.insert(pile)
            context.saveWithErrorHandling()
            return pile
        }
    }

    func saveAndActivate(context: ModelContext, allPiles: [PairsPile]) {
        let pile = save(context: context)
        for p in allPiles { p.isActive = false }
        pile.isActive = true
        context.saveWithErrorHandling()
    }
}
