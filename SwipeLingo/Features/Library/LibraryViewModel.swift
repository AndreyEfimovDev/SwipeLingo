import SwiftUI
import SwiftData

// MARK: - LibraryViewModel

@Observable
final class LibraryViewModel {
    var isShowingAddCollection = false
    var deletionError: String?
}
