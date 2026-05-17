import Foundation

// MARK: - AccessTier
// Контролирует доступ к контенту в зависимости от плана подписки пользователя.
// Применяется к CardSet и PairsSet.
// Планы: Free / Go / Pro

enum AccessTier: String, Codable, CaseIterable {
    case free  // бесплатный контент, доступен всем
    case go    // план Go  — бейдж "GO"  (myPurple → myBlue gradient)
    case pro   // план Pro — бейдж "PRO" (myYellow → myOrange gradient)

    // MARK: - Access control

    var rank: Int {
        switch self {
        case .free: return 0
        case .go:   return 1
        case .pro:  return 2
        }
    }

    /// Returns true if this plan covers the required tier.
    func canAccess(_ required: AccessTier) -> Bool { rank >= required.rank }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .go:   return "Go"
        case .pro:  return "Pro"
        }
    }

    func price(for cycle: BillingCycle) -> Double {
        switch (self, cycle) {
        case (.free, _):        return 0
        case (.go,  .monthly):  return 1.99
        case (.go,  .yearly):   return 19.99
        case (.pro, .monthly):  return 3.99
        case (.pro, .yearly):   return 39.99
        default:                return 0
        }
    }

    func priceString(for cycle: BillingCycle) -> String {
        let p = price(for: cycle)
        if p == 0 { return "Always free" }
        let period = cycle == .monthly ? "/ mo" : "/ year"
        return String(format: "$%.2f %@", p, period)
    }

    /// Placeholder prices — replace when StoreKit is integrated.
    var priceLabel: String { priceString(for: .yearly) }

    /// Calculates the charge for upgrading to `target`.
    /// Applies proration (credit for unused days) only when upgrading tier from a paid plan.
    static func chargeAmount(
        from current: AccessTier,
        currentCycle: BillingCycle,
        expiry: Date?,
        to target: AccessTier,
        targetCycle: BillingCycle
    ) -> Double {
        let fullPrice = target.price(for: targetCycle)
        // Proration only for tier upgrade from an active paid plan with known expiry
        guard target.rank > current.rank,
              current != .free,
              currentCycle != .none,
              let expiry else { return fullPrice }

        let periodDays: Double = currentCycle == .monthly ? 30 : 365
        let daysLeft   = max(0, expiry.timeIntervalSinceNow / 86_400)
        let credit     = (daysLeft / periodDays) * current.price(for: currentCycle)
        let charge     = max(0, fullPrice - credit)
        return (charge * 100).rounded() / 100
    }

    var features: [String] {
        switch self {
        case .free: return [
            "Your own flashcards",
            "Free content sets",
            "Spaced repetition (SRS)",
            "\(Constants.paywallPreviewLimit)-item preview of Go & Pro sets",
        ]
        case .go: return [
            "Everything in Free",
            "Full access to all Go sets",
            "\(Constants.paywallPreviewLimit)-item preview of Pro sets",
        ]
        case .pro: return [
            "Everything in Go",
            "Full access to all Pro sets",
            "Creating your own sets",
        ]
        }
    }
}
