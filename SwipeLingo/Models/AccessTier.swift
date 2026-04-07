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

    /// Placeholder prices — replace when StoreKit is integrated.
    var priceLabel: String {
        switch self {
        case .free: return "Always free"
        case .go:   return "$9.99 / year"
        case .pro:  return "$19.99 / year"
        }
    }

    var features: [String] {
        switch self {
        case .free: return [
            "Your own flashcards",
            "Free content sets",
            "Spaced repetition (SRS)",
            "8-card preview of Go & Pro sets",
        ]
        case .go: return [
            "Everything in Free",
            "Full access to all Go sets",
            "8-card preview of Pro sets",
        ]
        case .pro: return [
            "Everything in Go",
            "Full access to all Pro sets",
            "Creating your own sets",
        ]
        }
    }
}
