import SwiftUI
import SwiftData

// MARK: - PairsPileBuilderViewModel

@Observable
final class PairsPileBuilderViewModel {

    var name: String
    var selectedSetIds: Set<UUID>

    let editingPile: PairsPile?

    private let initialName: String
    private let initialSetIds: Set<UUID>

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedSetIds.isEmpty
    }

    var hasChanges: Bool {
        guard editingPile != nil else { return true }
        return name != initialName || selectedSetIds != initialSetIds
    }

    var canSave: Bool { isValid && hasChanges }

    init(editingPile: PairsPile? = nil) {
        self.editingPile    = editingPile
        self.name           = editingPile?.name ?? ""
        self.selectedSetIds = Set(editingPile?.setIds ?? [])
        self.initialName    = editingPile?.name ?? ""
        self.initialSetIds  = Set(editingPile?.setIds ?? [])
    }

    func toggleSet(_ id: UUID) {
        if selectedSetIds.contains(id) {
            selectedSetIds.remove(id)
        } else {
            selectedSetIds.insert(id)
        }
    }

    @discardableResult
    func save(context: ModelContext) -> PairsPile {
        if let pile = editingPile {
            pile.name      = name.trimmingCharacters(in: .whitespaces)
            pile.setIds    = Array(selectedSetIds)
            pile.updatedAt = .now
            context.saveWithErrorHandling()
            return pile
        } else {
            let pile = PairsPile(
                name: name.trimmingCharacters(in: .whitespaces),
                setIds: Array(selectedSetIds),
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
