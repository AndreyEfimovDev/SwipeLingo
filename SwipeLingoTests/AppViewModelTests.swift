import XCTest
@testable import SwipeLingo

// MARK: - AppViewModelTests
//
// Покрывает `AppViewModel.levelIncrease(oldRaw:newRaw:)` — чистую логику решения
// "нужен ли sync при смене CEFR-уровня" (см. handleCEFRLevelChange). Сам факт
// вызова ImportFSService().syncFromFirestore(...) не тестируется — у ImportFSService
// нет протокола-обёртки для моков (в отличие от AuthClient/FirestoreClient).

@MainActor
final class AppViewModelTests: XCTestCase {

    // MARK: - Повышение уровня

    func testLevelIncrease_HigherNewLevel_ReturnsNewLevel() {
        let result = AppViewModel.levelIncrease(oldRaw: "a1", newRaw: "b1")
        XCTAssertEqual(result, .b1)
    }

    func testLevelIncrease_InvalidOldRawValue_FallsBackToC2_TreatedAsNoIncrease() {
        // Невалидный oldRaw → фолбэк .c2 (максимум) — почти любой newRaw окажется
        // "понижением" относительно него, sync не запускается.
        let result = AppViewModel.levelIncrease(oldRaw: "не валидное значение", newRaw: "b1")
        XCTAssertNil(result)
    }

    func testLevelIncrease_InvalidNewRawValue_FallsBackToC2_TreatedAsIncrease() {
        // Невалидный newRaw → фолбэк .c2 — относительно валидного низкого oldRaw
        // это формально "повышение" (документирует фолбэк-поведение, не то, что
        // это желаемый сценарий — на практике newRaw невалидным не бывает).
        let result = AppViewModel.levelIncrease(oldRaw: "a1", newRaw: "не валидное значение")
        XCTAssertEqual(result, .c2)
    }

    // MARK: - Понижение уровня

    func testLevelIncrease_LowerNewLevel_ReturnsNil() {
        let result = AppViewModel.levelIncrease(oldRaw: "b1", newRaw: "a1")
        XCTAssertNil(result)
    }

    // MARK: - Без изменения уровня

    func testLevelIncrease_SameLevel_ReturnsNil() {
        let result = AppViewModel.levelIncrease(oldRaw: "b1", newRaw: "b1")
        XCTAssertNil(result)
    }

    // MARK: - nil-значения (профиль ещё не создан / первое наблюдение)

    func testLevelIncrease_BothNil_ReturnsNil() {
        // Оба фолбэчатся на .c2 — равны, не повышение.
        let result = AppViewModel.levelIncrease(oldRaw: nil, newRaw: nil)
        XCTAssertNil(result)
    }

    func testLevelIncrease_OldNil_ReturnsNil() {
        // oldRaw == nil → фолбэк .c2 (максимум) — любой реальный newRaw ниже,
        // т.е. "первое наблюдение уровня" никогда не трактуется как повышение
        // этим механизмом (первичная загрузка контента идёт отдельным путём —
        // syncForCurrentUser при завершении онбординга, не отсюда).
        let result = AppViewModel.levelIncrease(oldRaw: nil, newRaw: "a1")
        XCTAssertNil(result)
    }
}
