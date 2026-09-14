import XCTest
@testable import SwipeLingo

// MARK: - ErrorManagerTests
//
// Покрывает:
//   • notify(title:message:) — кастомный заголовок алерта, отдельно от handle(...)
//   • handle(...) — дефолтный заголовок "Error" (в т.ч. сбрасывает кастомный,
//     выставленный предыдущим notify), сообщение из Error.localizedDescription
//     либо из переданного message
//   • clear() — сбрасывает message/title/showAlert к дефолтам
//
// ErrorManager.shared — синглтон, общий для всех тестов процесса, поэтому
// setUp/tearDown приводят его к чистому состоянию перед и после каждого теста.

@MainActor
final class ErrorManagerTests: XCTestCase {

    override func setUpWithError() throws {
        ErrorManager.shared.clear()
    }

    override func tearDownWithError() throws {
        ErrorManager.shared.clear()
    }

    // MARK: - notify

    func testNotify_SetsCustomTitleAndMessage() {
        ErrorManager.shared.notify(title: "Sync Unavailable", message: "текст сообщения")

        XCTAssertEqual(ErrorManager.shared.errorTitle, "Sync Unavailable")
        XCTAssertEqual(ErrorManager.shared.errorMessage, "текст сообщения")
    }

    func testNotify_ShowsAlert() {
        ErrorManager.shared.notify(title: "Sync Unavailable", message: "текст")
        XCTAssertTrue(ErrorManager.shared.showAlert)
    }

    // MARK: - handle

    func testHandle_UsesDefaultTitle_EvenAfterPriorCustomTitle() {
        // Сначала выставляем кастомный заголовок через notify — handle() не должен
        // унаследовать его, а обязан вернуть дефолтное "Error".
        ErrorManager.shared.notify(title: "Sync Unavailable", message: "текст")
        ErrorManager.shared.handle(message: "обычная ошибка")

        XCTAssertEqual(ErrorManager.shared.errorTitle, "Error")
    }

    func testHandle_WithoutErrorObject_UsesProvidedMessage() {
        ErrorManager.shared.handle(message: "текст ошибки")
        XCTAssertEqual(ErrorManager.shared.errorMessage, "текст ошибки")
    }

    func testHandle_WithErrorObject_UsesLocalizedDescriptionInsteadOfMessage() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "описание ошибки"])
        ErrorManager.shared.handle(error, message: "запасной текст, не должен использоваться")

        XCTAssertEqual(ErrorManager.shared.errorMessage, "описание ошибки")
    }

    func testHandle_ShowsAlert() {
        ErrorManager.shared.handle(message: "текст")
        XCTAssertTrue(ErrorManager.shared.showAlert)
    }

    // MARK: - clear

    func testClear_ResetsMessageTitleAndShowAlert() {
        ErrorManager.shared.notify(title: "Sync Unavailable", message: "текст")

        ErrorManager.shared.clear()

        XCTAssertNil(ErrorManager.shared.errorMessage)
        XCTAssertEqual(ErrorManager.shared.errorTitle, "Error")
        XCTAssertFalse(ErrorManager.shared.showAlert)
    }
}
