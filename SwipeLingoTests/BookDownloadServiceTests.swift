import XCTest
@testable import SwipeLingo

// MARK: - BookDownloadServiceTests
//
// BookDownloadService.imageFileNames — какие картинки главы докачиваются в кэш:
//   • относительные ссылки "../images/{файл}" (как пишет Admin), в т.ч. в одинарных кавычках
//   • абсолютные (http, data:) и прочие пути не учитываются
//   • повторы схлопываются, порядок сохраняется

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
}
