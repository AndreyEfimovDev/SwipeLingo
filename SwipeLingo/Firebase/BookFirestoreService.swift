import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - BookFirestoreService
//
// Syncs books from Firestore /books collection into SwiftData.
//
// Firestore schema:
//   /books/{id}
//     title, author, description, cefrLevel, accessTier,
//     coverStoragePath, totalChapters,
//     chapters: [{index, title}],
//     updatedAt, createdAt
//
// Upsert logic: matches by firestoreId. Never deletes local books
// (user may have reading progress).

struct BookFirestoreService {

    private static let lastSyncAtKey = "booksLastSyncAt"

    // MARK: - Sync

    func syncBooks(into context: ModelContext, forceFullSync: Bool = false) async {
        guard FirebaseApp.app() != nil else {
            log("[Books] Firebase not configured — skipping sync", level: .warning)
            return
        }

        let db = Firestore.firestore()

        let lastSyncAt: Date = forceFullSync
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

            let existing = (try? context.fetch(FetchDescriptor<Book>())) ?? []
            let existingByFirestoreId = Dictionary(uniqueKeysWithValues: existing.map { ($0.firestoreId, $0) })

            for doc in snapshot.documents {
                guard let fsBook = parseBook(doc) else { continue }
                upsert(fsBook, into: context, existing: existingByFirestoreId)
            }

            try? context.save()
            UserDefaults.standard.set(Date.now, forKey: Self.lastSyncAtKey)
            log("[Books] Synced \(snapshot.documents.count) book(s)", level: .info)

        } catch {
            log("[Books] Sync failed: \(error)", level: .error)
        }
    }

    // MARK: - Upsert

    private func upsert(
        _ fsBook: FSBook,
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
