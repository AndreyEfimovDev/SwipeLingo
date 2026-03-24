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

    /// Non-nil when editing an existing Pile; nil when creating.
    let editingPile: Pile?

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedSetIds.isEmpty
    }

    // MARK: Init

    init(editingPile: Pile? = nil) {
        self.editingPile    = editingPile
        self.name           = editingPile?.name          ?? ""
        self.selectedSetIds = Set(editingPile?.setIds    ?? [])
        self.shuffleMethod  = editingPile?.shuffleMethod ?? .random
    }

    // MARK: Actions

    func toggleSet(_ id: UUID) {
        if selectedSetIds.contains(id) {
            selectedSetIds.remove(id)
        } else {
            selectedSetIds.insert(id)
        }
    }

    /// Persists the Pile (insert or update). Does NOT activate.
    @discardableResult
    func save(context: ModelContext) -> Pile {
        if let pile = editingPile {
            pile.name          = name.trimmingCharacters(in: .whitespaces)
            pile.setIds        = Array(selectedSetIds)
            pile.shuffleMethod = shuffleMethod
            pile.updatedAt     = .now
            try? context.save()
            return pile
        } else {
            let pile = Pile(
                name: name.trimmingCharacters(in: .whitespaces),
                setIds: Array(selectedSetIds),
                isActive: false,
                shuffleMethod: shuffleMethod
            )
            context.insert(pile)
            try? context.save()
            return pile
        }
    }

    /// Saves the Pile, then makes it the only active one.
    func saveAndActivate(context: ModelContext, allPiles: [Pile]) {
        let pile = save(context: context)
        for p in allPiles { p.isActive = false }
        pile.isActive = true
        try? context.save()
    }
}
