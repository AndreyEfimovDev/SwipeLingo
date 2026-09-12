import SwiftUI
import SwiftData

// MARK: - PileBuilderViewModel

@Observable
final class PileBuilderViewModel {

    // MARK: Form state

    var name: String
    var selectedSetIds: Set<UUID>
    var shuffleMethod: ShuffleMethod

    // MARK: Metadata

    /// Не nil при редактировании существующего Pile; nil при создании.
    let editingPile: Pile?

    private let initialName: String
    private let initialSetIds: Set<UUID>
    private let initialShuffleMethod: ShuffleMethod

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedSetIds.isEmpty
    }

    /// True, когда значения формы отличаются от сохранённого состояния.
    /// Для новых пайлов всегда true (любая заполненная форма — это изменение).
    var hasChanges: Bool {
        guard editingPile != nil else { return true }
        return name != initialName
            || selectedSetIds != initialSetIds
            || shuffleMethod != initialShuffleMethod
    }

    var canSave: Bool { isValid && hasChanges }

    // MARK: Init

    init(editingPile: Pile? = nil) {
        self.editingPile         = editingPile
        self.name                = editingPile?.name          ?? ""
        self.selectedSetIds      = Set(editingPile?.setIds    ?? [])
        self.shuffleMethod       = editingPile?.shuffleMethod ?? .random
        self.initialName         = editingPile?.name          ?? ""
        self.initialSetIds       = Set(editingPile?.setIds    ?? [])
        self.initialShuffleMethod = editingPile?.shuffleMethod ?? .random
    }

    // MARK: Actions

    func toggleSet(_ id: UUID) {
        if selectedSetIds.contains(id) {
            selectedSetIds.remove(id)
        } else {
            selectedSetIds.insert(id)
        }
    }

    /// Сохраняет Pile (insert или update). НЕ активирует.
    @discardableResult
    func save(context: ModelContext) -> Pile {
        if let pile = editingPile {
            pile.name          = name.trimmingCharacters(in: .whitespaces)
            pile.setIds        = Array(selectedSetIds)
            pile.shuffleMethod = shuffleMethod
            pile.updatedAt     = .now
            context.saveWithErrorHandling()
            return pile
        } else {
            let pile = Pile(
                name: name.trimmingCharacters(in: .whitespaces),
                setIds: Array(selectedSetIds),
                isActive: false,
                shuffleMethod: shuffleMethod
            )
            context.insert(pile)
            context.saveWithErrorHandling()
            return pile
        }
    }

    /// Сохраняет Pile, затем делает его единственным активным.
    func saveAndActivate(context: ModelContext, allPiles: [Pile]) {
        let pile = save(context: context)
        for p in allPiles { p.isActive = false }
        pile.isActive = true
        context.saveWithErrorHandling()
    }
}
