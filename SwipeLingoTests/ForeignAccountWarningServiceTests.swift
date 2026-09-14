import XCTest
@testable import SwipeLingo

// MARK: - ForeignAccountWarningServiceTests
//
// Покрывает:
//   • hasForeignData: false — алерт не показывается
//   • hasForeignData: true, первый вызов — алерт показывается, флаг в UserDefaults взводится
//   • hasForeignData: true, повторный вызов — no-op (флаг уже взведён)
//
// warnIfNeeded трогает два общих ресурса — реальный UserDefaults.standard (по ключу
// Constants.StorageKey.foreignAccountWarningShown) и синглтон ErrorManager.shared —
// setUp/tearDown сохраняют исходное значение ключа и восстанавливают его после
// каждого теста, чтобы не засорять реальные UserDefaults устройства/симулятора.

@MainActor
final class ForeignAccountWarningServiceTests: XCTestCase {

    private let key = Constants.StorageKey.foreignAccountWarningShown

    /// Было ли у ключа значение до теста — нужно, чтобы в tearDown либо вернуть
    /// прежнее значение, либо полностью удалить ключ (если его не было вовсе).
    private var hadPreviousValue = false
    private var previousValue = false

    override func setUpWithError() throws {
        hadPreviousValue = UserDefaults.standard.object(forKey: key) != nil
        previousValue = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        ErrorManager.shared.clear()
    }

    override func tearDownWithError() throws {
        if hadPreviousValue {
            UserDefaults.standard.set(previousValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        ErrorManager.shared.clear()
    }

    // MARK: - hasForeignData: false

    func testWarnIfNeeded_NoForeignData_DoesNotShowAlert() {
        ForeignAccountWarningService.warnIfNeeded(hasForeignData: false)
        XCTAssertFalse(ErrorManager.shared.showAlert)
    }

    func testWarnIfNeeded_NoForeignData_DoesNotSetFlag() {
        ForeignAccountWarningService.warnIfNeeded(hasForeignData: false)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
    }

    // MARK: - hasForeignData: true, первый вызов

    func testWarnIfNeeded_ForeignData_FirstCall_ShowsAlert() {
        ForeignAccountWarningService.warnIfNeeded(hasForeignData: true)

        XCTAssertTrue(ErrorManager.shared.showAlert)
        XCTAssertEqual(ErrorManager.shared.errorTitle, "Sync Unavailable")
    }

    func testWarnIfNeeded_ForeignData_FirstCall_SetsPersistedFlag() {
        ForeignAccountWarningService.warnIfNeeded(hasForeignData: true)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
    }

    // MARK: - hasForeignData: true, повторный вызов — no-op

    func testWarnIfNeeded_ForeignData_SecondCall_DoesNotShowAgain() {
        ForeignAccountWarningService.warnIfNeeded(hasForeignData: true)
        // Симулируем, что пользователь закрыл алерт (тапнул "OK" → ErrorAlertModifier
        // вызывает clear()) — без этого шага второй вызов и не мог бы ничего "показать
        // заново", showAlert уже был бы true с первого раза.
        ErrorManager.shared.clear()

        ForeignAccountWarningService.warnIfNeeded(hasForeignData: true)

        XCTAssertFalse(ErrorManager.shared.showAlert)
    }
}
