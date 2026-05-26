import Foundation
import SwiftData

// MARK: - BookChapter

struct BookChapter: Codable, Identifiable, Hashable {
    var index: Int
    var title: String
    var id: Int { index }
}

// MARK: - Book

@Model class Book {

    var id:                UUID
    var firestoreId:       String
    var title:             String
    var author:            String
    var bookDescription:   String?
    var cefrLevelRaw:      String
    var accessTierRaw:     String
    var coverStoragePath:   String          // Firebase Storage path or full HTTP URL
    var chapterBaseURL:     String          // "" = Firebase Storage; "https://..." = HTTP debug stub
    var totalChapters:      Int
    var chaptersJSON:       String          // JSON-encoded [BookChapter]
    var createdAt:          Date
    var updatedAt:          Date

    init(
        firestoreId:      String,
        title:            String,
        author:           String,
        description:      String? = nil,
        cefrLevel:        CEFRLevel,
        accessTier:       AccessTier,
        coverStoragePath: String,
        chapterBaseURL:   String = "",
        totalChapters:    Int,
        chapters:         [BookChapter],
        createdAt:        Date,
        updatedAt:        Date
    ) {
        self.id               = UUID()
        self.firestoreId      = firestoreId
        self.title            = title
        self.author           = author
        self.bookDescription  = description
        self.cefrLevelRaw     = cefrLevel.rawValue
        self.accessTierRaw    = accessTier.rawValue
        self.coverStoragePath = coverStoragePath
        self.chapterBaseURL   = chapterBaseURL
        self.totalChapters    = totalChapters
        self.chaptersJSON     = Self.encode(chapters)
        self.createdAt        = createdAt
        self.updatedAt        = updatedAt
    }

    // MARK: - Computed

    var cefrLevel: CEFRLevel   { CEFRLevel(rawValue: cefrLevelRaw)   ?? .a1 }
    var accessTier: AccessTier { AccessTier(rawValue: accessTierRaw) ?? .free }

    var chapters: [BookChapter] {
        guard let data = chaptersJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([BookChapter].self, from: data)
        else { return [] }
        return decoded
    }

    // MARK: - Helpers

    private static func encode(_ chapters: [BookChapter]) -> String {
        (try? JSONEncoder().encode(chapters))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    func chapterStoragePath(at index: Int) -> String {
        if chapterBaseURL.isEmpty {
            return "books/\(firestoreId)/chapters/\(index).html"
        }
        return "\(chapterBaseURL)/\(index).html"
    }
}
