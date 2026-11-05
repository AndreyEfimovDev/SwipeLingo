import Foundation
import SwiftData

// MARK: - BookCatalogDedupeService
//
// Схлопывает дубли книг каталога с одним `firestoreId`. Та же гонка CloudKit, что у коллекций и настроек
// (см. CollectionDedupeService): синк каталога вставляет книгу, не найдя её локально, а чуть позже CloudKit
// довозит запись той же книги из прошлой установки или с другого устройства.
//
// Выживает запись с самым свежим `updatedAt` — у неё актуальные метаданные из Firestore (содержимое книги
// живёт в Storage и в кэше на диске по firestoreId, а не в записи, поэтому «самая старая», как у коллекций,
// здесь не подходит). Прогресс чтения и закладки дублей переносятся на выжившую запись, кэш на диске общий.
//
// Stateless-структура: ModelContext передаётся параметром на каждый вызов.

struct BookCatalogDedupeService {

    /// Схлопывает книги с одинаковым `firestoreId` в одну, перенося на неё прогресс и закладки.
    /// Ничего не сохраняет и ничего не делает, если дублей нет.
    /// - Returns: число удалённых дублей.
    @discardableResult
    func mergeDuplicates(context: ModelContext) -> Int {
        let books = context.fetchWithErrorHandling(FetchDescriptor<Book>())
        let groups = Dictionary(grouping: books.filter { !$0.firestoreId.isEmpty }, by: \.firestoreId)
            .values.filter { $0.count > 1 }
        guard !groups.isEmpty else { return 0 }

        let progresses = context.fetchWithErrorHandling(FetchDescriptor<BookProgress>())
        let bookmarks  = context.fetchWithErrorHandling(FetchDescriptor<BookBookmark>())
        var removed = 0

        for group in groups {
            // Свежие метаданные; при равном updatedAt — более старая запись (стабильный выбор на всех устройствах).
            let sorted = group.sorted {
                $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.createdAt < $1.createdAt
            }
            guard let survivor = sorted.first else { continue }
            let duplicates = sorted.dropFirst()
            let duplicateIds = Set(duplicates.map(\.id))

            // Уже открытая хоть где-то книга не должна снова получить бейдж NEW.
            if duplicates.contains(where: { !$0.isNew }) { survivor.isNew = false }

            for bookmark in bookmarks where duplicateIds.contains(bookmark.bookId) {
                bookmark.bookId = survivor.id
            }
            mergeProgress(of: duplicateIds, into: survivor.id, progresses: progresses, context: context)

            for duplicate in duplicates { context.delete(duplicate) }
            removed += duplicates.count
            log("Merged \(group.count) copies of book '\(survivor.title)' → 1", level: .info)
        }
        context.saveWithErrorHandling()
        return removed
    }

    // MARK: - Private

    /// Переносит прогресс дублей на выжившую книгу; если прогрессов несколько, оставляет последний по `lastReadAt`.
    private func mergeProgress(of duplicateIds: Set<UUID>, into survivorId: UUID,
                               progresses: [BookProgress], context: ModelContext) {
        let related = progresses.filter { $0.bookId == survivorId || duplicateIds.contains($0.bookId) }
        guard let latest = related.max(by: { $0.lastReadAt < $1.lastReadAt }) else { return }
        latest.bookId = survivorId
        for progress in related where progress !== latest {
            context.delete(progress)
        }
    }
}
