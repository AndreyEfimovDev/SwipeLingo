#if DEBUG
import Foundation
import SwiftData

// MARK: - MockBookCatalog
//
// Мок-каталог книг для отладки — без Firestore и сети. Книги разных уровней и тарифов (Free/Go/Pro),
// чтобы были видны бейджи и paywall. HTML глав генерируется здесь и сразу пишется в локальный кэш
// BookDownloadService: downloadChapter пропускает уже существующие файлы, поэтому ридер работает
// как с настоящей книгой. Обложек нет — BookCard показывает свою заглушку.
// Недостающие файлы глав дописываются при каждом синке (после удаления книги или очистки кэша).

struct MockBookCatalog: BookCatalogSyncing {

    /// Где лежит локальный файл главы. По умолчанию — кэш BookDownloadService; в тестах — временная папка.
    private let chapterURL: (Book, Int) -> URL

    init(chapterURL: @escaping (Book, Int) -> URL = { BookDownloadService.shared.localChapterURL(book: $0, index: $1) }) {
        self.chapterURL = chapterURL
    }

    func syncBooks(into context: ModelContext) async {
        let existing = context.fetchWithErrorHandling(FetchDescriptor<Book>())
        let existingByFirestoreId = Dictionary(existing.map { ($0.firestoreId, $0) }, uniquingKeysWith: { first, _ in first })

        for mock in Self.books {
            let book = existingByFirestoreId[mock.id] ?? insertBook(mock, into: context)
            writeMissingChapters(of: mock, for: book)
        }
        context.saveWithErrorHandling()
        log("Mock catalog: \(Self.books.count) book(s)", level: .info)
    }

    // MARK: - Private

    private func insertBook(_ mock: MockBook, into context: ModelContext) -> Book {
        let book = Book(
            firestoreId:      mock.id,
            title:            mock.title,
            author:           mock.author,
            description:      mock.description,
            cefrLevel:        mock.level,
            accessTier:       mock.tier,
            coverStoragePath: "",
            totalChapters:    mock.chapters.count,
            chapters:         mock.chapters.enumerated().map { BookChapter(index: $0.offset, title: $0.element.title) },
            createdAt:        .now,
            updatedAt:        .now
        )
        context.insert(book)
        return book
    }

    private func writeMissingChapters(of mock: MockBook, for book: Book) {
        let fm = FileManager.default
        for (index, chapter) in mock.chapters.enumerated() {
            let url = chapterURL(book, index)
            guard !fm.fileExists(atPath: url.path) else { continue }
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(Self.html(title: chapter.title, paragraphs: chapter.paragraphs).utf8).write(to: url)
            } catch {
                log("Mock chapter write failed: \(error.localizedDescription)", level: .error)
            }
        }
    }

    private static func html(title: String, paragraphs: [String]) -> String {
        let body = paragraphs.map { "<p>\($0)</p>" }.joined(separator: "\n")
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(title)</title></head>
        <body><h1>\(title)</h1>
        \(body)
        </body></html>
        """
    }
}

// MARK: - Mock data

private struct MockBook {
    let id: String
    let title: String
    let author: String
    let description: String
    let level: CEFRLevel
    let tier: AccessTier
    let chapters: [(title: String, paragraphs: [String])]
}

private extension MockBookCatalog {

    static let books: [MockBook] = [
        MockBook(
            id: "mock-a2-lighthouse",
            title: "The Lighthouse Keeper",
            author: "Mock Author",
            description: "A quiet story about a man who looks after an old lighthouse.",
            level: .a2,
            tier: .free,
            chapters: [
                ("The Island", [
                    "Tom lives on a small island. There is one house, one garden and one tall white lighthouse.",
                    "Every evening he climbs the stairs and turns on the big lamp. Ships see the light and stay away from the rocks."
                ]),
                ("The Storm", [
                    "One night the wind is very strong. The rain hits the windows and the sea is loud.",
                    "Tom hears a small boat. He takes his coat and his torch and runs down to the beach."
                ]),
                ("Morning", [
                    "In the morning the sky is blue again. A young fisherman sits in Tom's kitchen with a cup of tea.",
                    "\"Thank you,\" he says. Tom smiles. \"That is my job.\""
                ])
            ]
        ),
        MockBook(
            id: "mock-b1-market",
            title: "The Night Market",
            author: "Mock Author",
            description: "Two friends find a market that only opens after midnight.",
            level: .b1,
            tier: .go,
            chapters: [
                ("Lost in the City", [
                    "Anna and Leo had missed the last train, so they decided to walk home through the old part of the city.",
                    "The streets were empty, but somewhere ahead they could hear music and people laughing."
                ]),
                ("Lanterns", [
                    "Around the corner, hundreds of paper lanterns lit up a narrow square full of stalls.",
                    "An old woman offered them a map. \"Everything here costs a memory,\" she said, \"not money.\""
                ])
            ]
        ),
        MockBook(
            id: "mock-c1-archive",
            title: "The Archivist",
            author: "Mock Author",
            description: "A librarian uncovers a correspondence that rewrites a family history.",
            level: .c1,
            tier: .pro,
            chapters: [
                ("An Unremarkable Box", [
                    "Nobody at the archive had paid much attention to the box: it was unlabelled, water-stained and conspicuously ordinary.",
                    "Yet the letters inside, bound with faded ribbon, were addressed to a woman whose existence the family had always denied."
                ]),
                ("Reading Between the Lines", [
                    "The handwriting grew increasingly hurried, as though the writer had been racing against some unspoken deadline.",
                    "By the final letter, the archivist realised she was no longer cataloguing a collection but reconstructing a life."
                ])
            ]
        )
    ]
}
#endif
