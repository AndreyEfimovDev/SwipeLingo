import Foundation
import SwiftData

// MARK: - BooksViewModel

@Observable
final class BooksViewModel {

    var searchText:    String       = ""
    var selectedLevel: CEFRLevel?   = nil
    var isSyncing:     Bool         = false
    var selectedBook:  Book?        = nil

    private let catalog: BookCatalogSyncing

    /// - Parameter catalog: источник каталога книг из composition root (мок в DEBUG, Firestore в релизе).
    init(catalog: BookCatalogSyncing) {
        self.catalog = catalog
    }

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
                // Сначала бесплатные, затем по CEFR-уровню
                if $0.accessTier.rank != $1.accessTier.rank {
                    return $0.accessTier.rank < $1.accessTier.rank
                }
                return $0.cefrLevel < $1.cefrLevel
            }
    }

    // MARK: - Download

    /// Удаляет скачанные главы книги с диска, освобождая место. Книга остаётся в каталоге (удалить запись
    /// нельзя: полный синк каталога вернул бы её), прогресс чтения и закладки сохраняются, обложка тоже.
    /// - Parameter book: книга каталога.
    func removeDownload(of book: Book) {
        BookDownloadService.shared.removeDownloadedChapters(of: book)
    }

    // MARK: - Sync

    /// Загружает каталог книг из внедрённого источника. Повторный вызов во время идущего синка игнорируется.
    func syncBooks(context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await catalog.syncBooks(into: context)
        mergeDuplicateBooks(context: context)
    }

    /// Схлопывает дубли книг с одним firestoreId — в т.ч. те, что CloudKit довёз уже после синка каталога.
    /// Вызывается после синка и при каждом появлении раздела Books (дёшево: книг единицы).
    func mergeDuplicateBooks(context: ModelContext) {
        BookCatalogDedupeService().mergeDuplicates(context: context)
    }
}
