import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - BookCatalogDedupeServiceTests
//
// Дубли книг с одним firestoreId (гонка CloudKit: синк каталога вставил книгу раньше, чем CloudKit довёз старую):
//   • выживает запись с самым свежим updatedAt (актуальные метаданные)
//   • прогресс и закладки дубля переносятся на выжившую; из двух прогрессов остаётся более свежий
//   • isNew сбрасывается, если хоть одна копия уже открывалась
//   • книги с разными firestoreId не трогаются; повторный вызов ничего не меняет

@MainActor
final class BookCatalogDedupeServiceTests: XCTestCase {

    private let service = BookCatalogDedupeService()

    func testDuplicates_FreshestUpdatedAtSurvives() throws {
        let context = try makeContext()
        let old = book("AESOP", title: "Old title", updatedAt: date(1))
        let fresh = book("AESOP", title: "New title", updatedAt: date(2))
        context.insert(old)
        context.insert(fresh)

        let removed = service.mergeDuplicates(context: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(books.map(\.title), ["New title"])
    }

    func testDuplicates_ProgressAndBookmarksMoveToSurvivor_LatestProgressKept() throws {
        let context = try makeContext()
        let old = book("AESOP", title: "Old", updatedAt: date(1))
        let fresh = book("AESOP", title: "New", updatedAt: date(2))
        context.insert(old)
        context.insert(fresh)
        let olderProgress = BookProgress(bookId: fresh.id, chapterIndex: 1)
        olderProgress.lastReadAt = date(10)
        let newerProgress = BookProgress(bookId: old.id, chapterIndex: 42)
        newerProgress.lastReadAt = date(20)
        context.insert(olderProgress)
        context.insert(newerProgress)
        context.insert(BookBookmark(bookId: old.id, chapterIndex: 5, chapterTitle: "Fox", scrollOffset: 0))
        let freshId = fresh.id

        service.mergeDuplicates(context: context)

        let progresses = try context.fetch(FetchDescriptor<BookProgress>())
        let bookmarks = try context.fetch(FetchDescriptor<BookBookmark>())
        XCTAssertEqual(progresses.count, 1)
        XCTAssertEqual(progresses.first?.bookId, freshId)
        XCTAssertEqual(progresses.first?.chapterIndex, 42)
        XCTAssertEqual(bookmarks.map(\.bookId), [freshId])
    }

    func testDuplicates_OpenedCopyClearsNewFlag() throws {
        let context = try makeContext()
        let opened = book("AESOP", title: "Old", updatedAt: date(1))
        opened.isNew = false
        let fresh = book("AESOP", title: "New", updatedAt: date(2))
        context.insert(opened)
        context.insert(fresh)

        service.mergeDuplicates(context: context)

        let survivor = try XCTUnwrap(context.fetch(FetchDescriptor<Book>()).first)
        XCTAssertFalse(survivor.isNew)
    }

    func testDifferentBooks_Untouched_SecondRunNoOp() throws {
        let context = try makeContext()
        context.insert(book("AESOP", title: "Aesop", updatedAt: date(1)))
        context.insert(book("LIGHTHOUSE", title: "Lighthouse", updatedAt: date(1)))

        XCTAssertEqual(service.mergeDuplicates(context: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Book>()).count, 2)
        XCTAssertEqual(service.mergeDuplicates(context: context), 0)
    }

    // MARK: - Helpers

    private func book(_ firestoreId: String, title: String, updatedAt: Date) -> Book {
        Book(firestoreId: firestoreId, title: title, author: "Aesop", cefrLevel: .a1, accessTier: .free,
             coverStoragePath: "", totalChapters: 0, chapters: [], createdAt: date(0), updatedAt: updatedAt)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_000_000 + seconds)
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, BookProgress.self, BookBookmark.self, configurations: config)
        return ModelContext(container)
    }
}
