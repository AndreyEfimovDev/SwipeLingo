import XCTest
@testable import SwipeLingo

// MARK: - BookDownloadServiceTests
//
// BookDownloadService.imageFileNames — какие картинки главы докачиваются в кэш:
//   • относительные ссылки "../images/{файл}" (как пишет Admin), в т.ч. в одинарных кавычках
//   • абсолютные (http, data:) и прочие пути не учитываются
//   • повторы схлопываются, порядок сохраняется
// removeDownloadedChapters — «Remove download»: главы и картинки удаляются, обложка остаётся

@MainActor
final class BookDownloadServiceTests: XCTestCase {

    func testImageFileNames_RelativeImagesOnly_NoDuplicates() {
        let html = """
        <p>Text</p>
        <img src="../images/fox.jpg" alt="Fox">
        <IMG class="wide" SRC='../images/crow.png'>
        <img src="https://example.com/remote.jpg">
        <img src="data:image/png;base64,AAAA">
        <img src="images/local.jpg">
        <img src="../images/fox.jpg">
        """

        XCTAssertEqual(BookDownloadService.imageFileNames(inChapterHTML: html), ["fox.jpg", "crow.png"])
    }

    func testImageFileNames_NoImages_Empty() {
        XCTAssertEqual(BookDownloadService.imageFileNames(inChapterHTML: "<h1>Title</h1><p>Text</p>"), [])
    }

    // MARK: - removeDownloadedChapters

    func testRemoveDownloadedChapters_RemovesChaptersAndImages_KeepsCover() throws {
        let service = BookDownloadService.shared
        let book = Book(firestoreId: "TEST_\(UUID().uuidString)", title: "Test", author: "Author", cefrLevel: .a1,
                        accessTier: .free, coverStoragePath: "", totalChapters: 1, chapters: [],
                        createdAt: .now, updatedAt: .now)
        defer { service.clearCache(firestoreId: book.firestoreId) }
        let fm = FileManager.default
        let chapter = service.localChapterURL(book: book, index: 0)
        let image = service.localBookDirectory(book: book).appendingPathComponent("images/fox.jpg")
        let cover = service.localCoverURL(book: book)
        for url in [chapter, image, cover] {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }

        service.removeDownloadedChapters(of: book)

        XCTAssertFalse(fm.fileExists(atPath: chapter.path))
        XCTAssertFalse(fm.fileExists(atPath: image.path))
        XCTAssertTrue(fm.fileExists(atPath: cover.path))
    }
}
