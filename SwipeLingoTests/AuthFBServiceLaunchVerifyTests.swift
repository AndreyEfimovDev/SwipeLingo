import XCTest
@testable import SwipeLingo

// MARK: - AuthFBServiceLaunchVerifyTests
//
// AuthFBService.shouldSignOut(afterLaunchVerifyError:) — выход из аккаунта после проверки сессии на старте:
//   • сетевые ошибки, таймаут, TLS, неизвестные коды — сессия сохраняется
//     (регрессия: networkError 17020 с вложенным -1200 при VPN в авиарежиме разлогинивал пользователя)
//   • явные ошибки авторизации (пользователь удалён/отключён, токен недействителен/истёк) — выход
//
// Коды и домен — значения FirebaseAuth (AuthErrors.domain, AuthErrorCode) напрямую: тестовый таргет
// не импортирует Firebase.

@MainActor
final class AuthFBServiceLaunchVerifyTests: XCTestCase {

    private let authDomain = "FIRAuthErrorDomain"

    func testNetworkErrorWithTLSFailure_KeepsSession() {
        let tls = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed)
        let error = authError(17020, underlying: tls)   // networkError + -1200

        XCTAssertFalse(AuthFBService.shouldSignOut(afterLaunchVerifyError: error))
    }

    func testNetworkErrorWithoutUnderlying_KeepsSession() {
        XCTAssertFalse(AuthFBService.shouldSignOut(afterLaunchVerifyError: authError(17020)))
    }

    func testOwnTimeout_KeepsSession() {
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)

        XCTAssertFalse(AuthFBService.shouldSignOut(afterLaunchVerifyError: timeout))
    }

    func testUnknownError_KeepsSession() {
        XCTAssertFalse(AuthFBService.shouldSignOut(afterLaunchVerifyError: NSError(domain: "SomeOtherDomain", code: 17011)))
        XCTAssertFalse(AuthFBService.shouldSignOut(afterLaunchVerifyError: authError(17999)))   // internalError
    }

    func testExplicitAuthErrors_SignOut() {
        // userNotFound, userDisabled, invalidUserToken, userTokenExpired
        for code in [17011, 17005, 17017, 17021] {
            XCTAssertTrue(AuthFBService.shouldSignOut(afterLaunchVerifyError: authError(code)), "code \(code)")
        }
    }

    // MARK: - Helpers

    private func authError(_ code: Int, underlying: NSError? = nil) -> NSError {
        NSError(domain: authDomain, code: code, userInfo: underlying.map { [NSUnderlyingErrorKey: $0] } ?? [:])
    }
}
