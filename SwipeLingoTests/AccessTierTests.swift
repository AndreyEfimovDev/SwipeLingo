import XCTest
@testable import SwipeLingo

// MARK: - AccessTierTests
//
// AccessTier.canAccess — доступ к контенту по плану:
//   • монетизация выключена (первый релиз бесплатный) — любой план открывает любой контент
//   • монетизация включена — план открывает контент своего ранга и ниже
//   • в текущей сборке выключатель стоит в «выключено» — защита от случайного включения без оплаты

@MainActor
final class AccessTierTests: XCTestCase {

    func testMonetizationDisabled_EveryPlanOpensEverything() {
        for plan in AccessTier.allCases {
            for required in AccessTier.allCases {
                XCTAssertTrue(plan.canAccess(required, monetizationEnabled: false), "\(plan) → \(required)")
            }
        }
    }

    func testMonetizationEnabled_PlanOpensOwnRankAndBelow() {
        XCTAssertTrue(AccessTier.free.canAccess(.free, monetizationEnabled: true))
        XCTAssertFalse(AccessTier.free.canAccess(.go, monetizationEnabled: true))
        XCTAssertFalse(AccessTier.free.canAccess(.pro, monetizationEnabled: true))
        XCTAssertTrue(AccessTier.go.canAccess(.go, monetizationEnabled: true))
        XCTAssertFalse(AccessTier.go.canAccess(.pro, monetizationEnabled: true))
        XCTAssertTrue(AccessTier.pro.canAccess(.free, monetizationEnabled: true))
        XCTAssertTrue(AccessTier.pro.canAccess(.pro, monetizationEnabled: true))
    }

    func testCurrentBuild_MonetizationDisabled_FreeOpensPro() {
        XCTAssertFalse(Monetization.isEnabled)
        XCTAssertTrue(AccessTier.free.canAccess(.pro))
    }
}
