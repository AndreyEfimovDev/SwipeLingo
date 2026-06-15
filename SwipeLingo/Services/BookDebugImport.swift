import Foundation
import SwiftData

// MARK: - BookDebugImport
//
// Creates a test Book record from a GitHub-hosted export (metadata.json).
// Used for debugging the reader without Firebase Storage.
//
// Usage: BookDebugImport.importFromMetadataURL(metadataURL, context: context)

struct BookDebugImport {

    static func importBook(metadataURL: URL, context: ModelContext) async throws {
        let (data, _) = try await URLSession.shared.data(from: metadataURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BookDebugError.invalidJSON
        }

        let firestoreId    = json["firestoreId"]    as? String ?? UUID().uuidString
        let title          = json["title"]          as? String ?? "Untitled"
        let author         = json["author"]         as? String ?? "Unknown"
        let description    = json["description"]    as? String
        let cefrRaw        = json["cefrLevel"]      as? String ?? "a1"
        let accessRaw      = json["accessTier"]     as? String ?? "free"
        let coverURL       = json["coverURL"]       as? String ?? ""
        let chapterBaseURL = json["chapterBaseURL"] as? String ?? ""
        let totalChapters  = json["totalChapters"]  as? Int    ?? 0

        let chaptersRaw    = json["chapters"] as? [[String: Any]] ?? []
        let chapters       = chaptersRaw.compactMap { d -> BookChapter? in
            guard let index = d["index"] as? Int,
                  let title = d["title"] as? String else { return nil }
            return BookChapter(index: index, title: title)
        }

        // Remove existing book with same firestoreId
        let existing = try context.fetch(FetchDescriptor<Book>())
        existing.filter { $0.firestoreId == firestoreId }.forEach { context.delete($0) }

        let book = Book(
            firestoreId:      firestoreId,
            title:            title,
            author:           author,
            description:      description?.isEmpty == false ? description : nil,
            cefrLevel:        CEFRLevel(rawValue: cefrRaw) ?? .a1,
            accessTier:       AccessTier(rawValue: accessRaw) ?? .free,
            coverStoragePath: coverURL,
            chapterBaseURL:   chapterBaseURL,
            totalChapters:    totalChapters,
            chapters:         chapters,
            createdAt:        .now,
            updatedAt:        .now
        )
        context.insert(book)
        try context.save()
        log("[BookDebug] Imported '\(title)' (\(totalChapters) chapters)", level: .info)
    }
}

enum BookDebugError: LocalizedError {
    case invalidJSON
    var errorDescription: String? { "Invalid metadata.json format" }
}
