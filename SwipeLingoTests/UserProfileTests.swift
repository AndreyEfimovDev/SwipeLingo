import XCTest
@testable import SwipeLingo

// MARK: - UserProfileTests
//
// Покрывает:
//   • touch() — явно продвигает updatedAt (didSet на @Model-свойствах SwiftData
//     не гарантирует срабатывание — подтверждено этими же тестами до фикса:
//     didSet молча не срабатывал вовсе, — поэтому обновление updatedAt теперь
//     явный вызов touch() в местах мутации, не автоматика на самих полях)
//   • cefrLevel — get/set обёртка над cefrLevelRaw, с фолбэком на .a1 при
//     невалидном rawValue
//   • displayName — фолбэк на "Anonymous" при пустом/пробельном name
//
// updatedAt "состариваем" напрямую (Date.distantPast) вместо ненадёжных задержек
// через реальное время — тест детерминирован независимо от скорости выполнения.

@MainActor
final class UserProfileTests: XCTestCase {

    // MARK: - touch()

    func testTouch_AdvancesUpdatedAt() {
        let profile = UserProfile()
        profile.updatedAt = Date.distantPast

        profile.touch()

        XCTAssertGreaterThan(profile.updatedAt, Date.distantPast)
    }

    func testSettingFieldsWithoutTouch_DoesNotAdvanceUpdatedAt() {
        // Фиксирует контракт явно: сама по себе мутация name/cefrLevel/firebaseUID
        // НЕ трогает updatedAt — только отдельный вызов touch() после неё.
        let profile = UserProfile()
        profile.updatedAt = Date.distantPast

        profile.name = "Andrey"
        profile.cefrLevel = .b1
        profile.firebaseUID = "uid1"

        XCTAssertEqual(profile.updatedAt, Date.distantPast)
    }

    // MARK: - cefrLevel

    func testCefrLevel_GetterDecodesRawValue() {
        let profile = UserProfile(level: .b2)
        XCTAssertEqual(profile.cefrLevel, .b2)
    }

    func testCefrLevel_SetterUpdatesRawValue() {
        let profile = UserProfile(level: .a1)
        profile.cefrLevel = .c1
        XCTAssertEqual(profile.cefrLevelRaw, CEFRLevel.c1.rawValue)
    }

    func testCefrLevel_InvalidRawValue_FallsBackToA1() {
        let profile = UserProfile()
        profile.cefrLevelRaw = "не валидное значение"
        XCTAssertEqual(profile.cefrLevel, .a1)
    }

    // MARK: - displayName

    func testDisplayName_EmptyName_ReturnsAnonymous() {
        let profile = UserProfile(name: "")
        XCTAssertEqual(profile.displayName, "Anonymous")
    }

    func testDisplayName_WhitespaceOnlyName_ReturnsAnonymous() {
        let profile = UserProfile(name: "   ")
        XCTAssertEqual(profile.displayName, "Anonymous")
    }

    func testDisplayName_NonEmptyName_ReturnsTrimmedName() {
        let profile = UserProfile(name: "  Andrey  ")
        XCTAssertEqual(profile.displayName, "Andrey")
    }
}
