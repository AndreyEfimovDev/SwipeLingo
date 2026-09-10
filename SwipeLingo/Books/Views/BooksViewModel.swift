import Foundation
import SwiftData

// MARK: - BooksViewModel

@Observable
final class BooksViewModel {

    var searchText:    String       = ""
    var selectedLevel: CEFRLevel?   = nil
    var isSyncing:     Bool         = false
    var selectedBook:  Book?        = nil

    // MARK: - Filtered books

    func filteredBooks(_ books: [Book], userPlan: AccessTier) -> [Book] {
        books
            .filter { book in
                let matchesSearch = searchText.isEmpty
                    || book.title.localizedCaseInsensitiveContains(searchText)
                    || book.author.localizedCaseInsensitiveContains(searchText)
                let matchesLevel = selectedLevel == nil || book.cefrLevel == selectedLevel
                return matchesSearch && matchesLevel
            }
            .sorted {
                // Free first, then by CEFR level
                if $0.accessTier.rank != $1.accessTier.rank {
                    return $0.accessTier.rank < $1.accessTier.rank
                }
                return $0.cefrLevel < $1.cefrLevel
            }
    }

    // MARK: - Sync

    func syncBooks(context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await BookFirestoreService().syncBooks(into: context)
    }
}
