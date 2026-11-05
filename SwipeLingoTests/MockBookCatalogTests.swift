import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - MockBookCatalogTests
//
// Мок-каталог книг (DEBUG):
//   • повторный синк не создаёт дубли книг
//   • после синка файлы всех глав лежат в кэше; удалённый файл дописывается следующим синком

@MainActor
final class MockBookCatalogTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSyncTwice_NoDuplicateBooks() async throws {
        let context = try makeContext()
        let catalog = makeCatalog()

        await catalog.syncBooks(into: context)
        let firstCount = try context.fetch(FetchDescriptor<Book>()).count
        await catalog.syncBooks(into: context)
        let books = try context.fetch(FetchDescriptor<Book>())

        XCTAssertGreaterThan(firstCount, 0)
        XCTAssertEqual(books.count, firstCount)
        XCTAssertEqual(Set(books.map(\.firestoreId)).count, books.count)
    }

    func testSync_WritesAllChapters_AndRestoresDeletedOne() async throws {
        let context = try makeContext()
        let catalog = makeCatalog()

        await catalog.syncBooks(into: context)
        let books = try context.fetch(FetchDescriptor<Book>())
        for book in books {
            XCTAssertEqual(book.chapters.count, book.totalChapters)
            for index in 0..<book.totalChapters {
                XCTAssertTrue(FileManager.default.fileExists(atPath: chapterURL(book, index).path))
            }
        }

        let book = try XCTUnwrap(books.first)
        try FileManager.default.removeItem(at: chapterURL(book, 0))
        await catalog.syncBooks(into: context)

        XCTAssertTrue(FileManager.default.fileExists(atPath: chapterURL(book, 0).path))
    }

    // MARK: - Helpers

    private func makeCatalog() -> MockBookCatalog {
        MockBookCatalog(chapterURL: { [tempDir] book, index in
            tempDir!.appendingPathComponent(book.firestoreId).appendingPathComponent("\(index).html")
        })
    }

    private func chapterURL(_ book: Book, _ index: Int) -> URL {
        tempDir.appendingPathComponent(book.firestoreId).appendingPathComponent("\(index).html")
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, configurations: config)
        return ModelContext(container)
    }
}
