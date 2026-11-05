import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - BookFBService
//
// Синхронизирует книги из коллекции Firestore /books в SwiftData.
//
// Схема Firestore:
//   /books/{id}
//     title, author, description, cefrLevel, accessTier,
//     coverStoragePath, totalChapters,
//     chapters: [{index, title}],
//     isPublished,
//     updatedAt, createdAt
//
// Синк всегда полный: каталог — единицы документов, а дельта по updatedAt не сообщает об удалённых и снятых
// с публикации книгах. Upsert — по firestoreId. После успешного запроса с сервера локальные книги, которых
// нет в каталоге или которые сняты с публикации (для не-тестировщика), удаляются вместе с главами на диске,
// прогрессом и закладками — так из Admin можно убрать книгу у всех. Неопубликованные книги загружаются
// только тестировщику — см. BookCatalogVisibility.

struct BookFBService: BookCatalogSyncing {

    /// Firebase UID текущего пользователя — по нему решается, видны ли черновики книг.
    private let currentUID: @MainActor () -> String?

    /// - Parameter currentUID: UID текущего пользователя из AuthFBService (composition root).
    init(currentUID: @escaping @MainActor () -> String?) {
        self.currentUID = currentUID
    }

    // MARK: - Sync

    func syncBooks(into context: ModelContext) async {
        guard FirebaseApp.app() != nil else {
            log("Firebase not configured — skipping sync", level: .warning)
            return
        }

        let db = Firestore.firestore()
        let isTester = BookCatalogVisibility.isTester(uid: currentUID())

        do {
            let snapshot = try await db.collection("books").getDocuments()

            // Сначала схлопываем дубли (гонка CloudKit), затем строим словарь без падения на повторе ключа:
            // uniqueKeysWithValues трапит на дубле, а он мог появиться между дедупом и fetch.
            BookCatalogDedupeService().mergeDuplicates(context: context)
            let existing = (try? context.fetch(FetchDescriptor<Book>())) ?? []
            let existingByFirestoreId = Dictionary(existing.map { ($0.firestoreId, $0) }, uniquingKeysWith: { first, _ in first })

            var skippedIds = Set<String>()
            for doc in snapshot.documents {
                guard let fsBook = parseBook(doc) else { continue }
                switch BookCatalogVisibility.decide(isPublished: fsBook.isPublished, isTester: isTester) {
                case .show(let isTesting):
                    upsert(fsBook, isTesting: isTesting, into: context, existing: existingByFirestoreId)
                case .skip:
                    skippedIds.insert(fsBook.id)
                }
            }

            // Без сети Firestore молча отдаёт кэш (возможно, пустой или устаревший) — по нему не удаляем ничего.
            if snapshot.metadata.isFromCache {
                log("Books snapshot from cache — removal skipped", level: .warning)
            } else {
                let removeIds = BookCatalogVisibility.firestoreIdsToRemove(
                    localIds: existing.map(\.firestoreId),
                    catalogIds: Set(snapshot.documents.map(\.documentID)),
                    skippedIds: skippedIds
                )
                removeBooks(existing.filter { removeIds.contains($0.firestoreId) }, from: context)
            }

            // При ошибке сохранения — откат, чтобы автосохранение не записало синк наполовину.
            guard context.saveWithErrorHandling() else {
                context.rollback()
                log("Books not saved — rolled back", level: .error)
                return
            }
            log("Synced \(snapshot.documents.count) book(s)", level: .info)

        } catch {
            log("Sync failed: \(error)", level: .error)
        }
    }

    // MARK: - Removal

    /// Удаляет книги, убранные из каталога: записи, их прогресс и закладки, папку книги на диске.
    /// Не сохраняет контекст — это делает `syncBooks`.
    private func removeBooks(_ books: [Book], from context: ModelContext) {
        guard !books.isEmpty else { return }
        let bookIds = Set(books.map(\.id))
        let progresses = context.fetchWithErrorHandling(FetchDescriptor<BookProgress>())
        let bookmarks  = context.fetchWithErrorHandling(FetchDescriptor<BookBookmark>())
        progresses.filter { bookIds.contains($0.bookId) }.forEach { context.delete($0) }
        bookmarks.filter { bookIds.contains($0.bookId) }.forEach { context.delete($0) }
        for book in books {
            BookDownloadService.shared.clearCache(firestoreId: book.firestoreId)
            log("Removed book '\(book.title)' — no longer in catalog", level: .info)
            context.delete(book)
        }
    }

    // MARK: - Upsert

    private func upsert(
        _ fsBook: FSBook,
        isTesting: Bool,
        into context: ModelContext,
        existing: [String: Book]
    ) {
        let chapters = fsBook.chapters.map { BookChapter(index: $0.index, title: $0.title) }

        if let local = existing[fsBook.id] {
            local.title            = fsBook.title
            local.author           = fsBook.author
            local.bookDescription  = fsBook.description
            local.cefrLevelRaw     = fsBook.cefrLevel.rawValue
            local.accessTierRaw    = fsBook.accessTier.rawValue
            local.coverStoragePath = fsBook.coverStoragePath
            local.totalChapters    = fsBook.totalChapters
            local.chaptersJSON     = encodeChapters(chapters)
            local.updatedAt        = fsBook.updatedAt
            local.isTesting        = isTesting
        } else {
            let book = Book(
                firestoreId:      fsBook.id,
                title:            fsBook.title,
                author:           fsBook.author,
                description:      fsBook.description,
                cefrLevel:        fsBook.cefrLevel,
                accessTier:       fsBook.accessTier,
                coverStoragePath: fsBook.coverStoragePath,
                totalChapters:    fsBook.totalChapters,
                chapters:         chapters,
                isTesting:        isTesting,
                createdAt:        fsBook.createdAt,
                updatedAt:        fsBook.updatedAt
            )
            context.insert(book)
        }
    }

    // MARK: - Parsing

    private func parseBook(_ doc: QueryDocumentSnapshot) -> FSBook? {
        let d = doc.data()
        guard
            let title            = d["title"]            as? String,
            let author           = d["author"]           as? String,
            let cefrRaw          = d["cefrLevel"]         as? String,
            let cefrLevel        = CEFRLevel(rawValue: cefrRaw),
            let tierRaw          = d["accessTier"]        as? String,
            let accessTier       = AccessTier(rawValue: tierRaw),
            let coverStoragePath = d["coverStoragePath"]  as? String,
            let totalChapters    = d["totalChapters"]     as? Int,
            let updatedAtTS      = d["updatedAt"]         as? Timestamp,
            let createdAtTS      = d["createdAt"]         as? Timestamp
        else { return nil }

        let chaptersRaw = d["chapters"] as? [[String: Any]] ?? []
        let chapters: [FSBookChapter] = chaptersRaw.compactMap { item in
            guard
                let index = item["index"] as? Int,
                let title = item["title"] as? String
            else { return nil }
            return FSBookChapter(index: index, title: title)
        }

        return FSBook(
            id:               doc.documentID,
            title:            title,
            author:           author,
            description:      d["description"] as? String,
            cefrLevel:        cefrLevel,
            accessTier:       accessTier,
            coverStoragePath: coverStoragePath,
            totalChapters:    totalChapters,
            chapters:         chapters,
            isPublished:      d["isPublished"] as? Bool,
            updatedAt:        updatedAtTS.dateValue(),
            createdAt:        createdAtTS.dateValue()
        )
    }

    // MARK: - Helpers

    private func encodeChapters(_ chapters: [BookChapter]) -> String {
        (try? JSONEncoder().encode(chapters))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}
