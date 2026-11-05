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
// Логика upsert: сопоставление по firestoreId. Никогда не удаляет локальные книги
// (у пользователя может быть прогресс чтения). Неопубликованные книги загружаются только
// тестировщику — см. BookCatalogVisibility.

struct BookFBService: BookCatalogSyncing {

    private static let lastSyncAtKey = "booksLastSyncAt"

    /// Firebase UID текущего пользователя — по нему решается, видны ли черновики книг.
    private let currentUID: @MainActor () -> String?

    /// - Parameter currentUID: UID текущего пользователя из AuthFBService (composition root).
    init(currentUID: @escaping @MainActor () -> String?) {
        self.currentUID = currentUID
    }

    // MARK: - Sync

    func syncBooks(into context: ModelContext, forceFullSync: Bool = false) async {
        guard FirebaseApp.app() != nil else {
            log("Firebase not configured — skipping sync", level: .warning)
            return
        }

        let db = Firestore.firestore()
        let isTester = BookCatalogVisibility.isTester(uid: currentUID())

        // Тестировщику — всегда полный синк: дельта по updatedAt не вернёт черновики, залитые до его входа
        // в аккаунт, и не снимет плашку TESTING. Книг единицы, полный запрос дешёвый.
        let lastSyncAt: Date = forceFullSync || isTester
            ? .distantPast
            : (UserDefaults.standard.object(forKey: Self.lastSyncAtKey) as? Date ?? .distantPast)

        do {
            let snapshot: QuerySnapshot
            if lastSyncAt > .distantPast {
                snapshot = try await db.collection("books")
                    .whereField("updatedAt", isGreaterThan: Timestamp(date: lastSyncAt))
                    .getDocuments()
            } else {
                snapshot = try await db.collection("books").getDocuments()
            }

            // Сначала схлопываем дубли (гонка CloudKit), затем строим словарь без падения на повторе ключа:
            // uniqueKeysWithValues трапит на дубле, а он мог появиться между дедупом и fetch.
            BookCatalogDedupeService().mergeDuplicates(context: context)
            let existing = (try? context.fetch(FetchDescriptor<Book>())) ?? []
            let existingByFirestoreId = Dictionary(existing.map { ($0.firestoreId, $0) }, uniquingKeysWith: { first, _ in first })

            for doc in snapshot.documents {
                guard let fsBook = parseBook(doc) else { continue }
                switch BookCatalogVisibility.decide(isPublished: fsBook.isPublished, isTester: isTester) {
                case .show(let isTesting):
                    upsert(fsBook, isTesting: isTesting, into: context, existing: existingByFirestoreId)
                case .skip:
                    continue
                }
            }

            try? context.save()
            UserDefaults.standard.set(Date.now, forKey: Self.lastSyncAtKey)
            log("Synced \(snapshot.documents.count) book(s)", level: .info)

        } catch {
            log("Sync failed: \(error)", level: .error)
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
