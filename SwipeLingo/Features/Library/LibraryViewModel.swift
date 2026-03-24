import SwiftUI
import SwiftData

// MARK: - LibraryViewModel

@Observable
final class LibraryViewModel {
    var isShowingAddCollection = false
    var isShowingPileBuilder   = false
    /// Non-nil when editing an existing pile; nil when creating a new one.
    var editingPile: Pile?
    var deletionError: String?
}
