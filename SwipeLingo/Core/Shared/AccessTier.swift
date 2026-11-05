import Foundation

// MARK: - Monetization

/// Единый выключатель монетизации. Пока `false` (первый релиз бесплатный — решение 2026-11-05):
/// весь контент доступен независимо от плана, подписка из Firestore не читается, экраны Plans/Payment
/// недостижимы. Бейджи GO/PRO на сетах и книгах показываются и при выключенной монетизации — осознанно.
/// Включать вместе с настоящей оплатой (StoreKit или внешней по entitlement), не раньше.
enum Monetization {
    static let isEnabled = false
}

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

    /// Возвращает true, если этот план открывает контент уровня `required`. При выключенной монетизации
    /// (`Monetization.isEnabled == false`) — всегда true.
    func canAccess(_ required: AccessTier) -> Bool {
        canAccess(required, monetizationEnabled: Monetization.isEnabled)
    }

    /// Проверка доступа с явным положением выключателя — чтобы тест проверил обе ветки.
    /// - Parameters:
    ///   - required: уровень доступа контента.
    ///   - monetizationEnabled: включена ли монетизация.
    /// - Returns: true, если монетизация выключена или ранг плана не ниже требуемого.
    func canAccess(_ required: AccessTier, monetizationEnabled: Bool) -> Bool {
        !monetizationEnabled || rank >= required.rank
    }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .go:   return "Go"
        case .pro:  return "Pro"
        }
    }

#if os(iOS)
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

    /// Временные цены — заменить, когда будет подключён StoreKit.
    var priceLabel: String { priceString(for: .yearly) }

    /// Вычисляет сумму к оплате при апгрейде до `target`.
    /// Применяет proration (зачёт за неиспользованные дни) только при апгрейде уровня с платного плана.
    static func chargeAmount(
        from current: AccessTier,
        currentCycle: BillingCycle,
        expiry: Date?,
        to target: AccessTier,
        targetCycle: BillingCycle
    ) -> Double {
        let fullPrice = target.price(for: targetCycle)
        // Proration только при апгрейде уровня с активного платного плана с известной датой истечения
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
#endif
}
