import Foundation

// MARK: - SRS Rating

/// Three-button spaced-repetition rating (maps to SM-2 quality values).
enum SRSRating {
    case again  // Не знал — EF −0.20, full reset
    case hard   // Сложно  — EF −0.15, hold interval
    case easy   // Легко   — EF +0.10, advance interval
}

// MARK: - SRSService

/// Implements the SM-2 spaced-repetition algorithm.
/// All mutations happen directly on the @Model Card instance.
/// Must be called on the same actor that owns the ModelContext (MainActor by default).
struct SRSService {

    private static let efMin: Double = 1.3

    // MARK: - Public API

    /// Applies SM-2 to `card`, mutating its SRS fields in place.
    /// The caller is responsible for saving the ModelContext afterwards.
    func evaluate(card: Card, rating: SRSRating) {
        let now = Date.now
        card.lastReviewed = now

        switch rating {

        case .again:
            // Forgot completely — penalise EF and reset streak
            card.easeFactor  = max(Self.efMin, card.easeFactor - 0.20)
            card.repetitions = 0
            card.interval    = 1

        case .hard:
            // Recalled with difficulty — penalise EF, halve the interval
            card.easeFactor = max(Self.efMin, card.easeFactor - 0.15)
            card.interval   = max(1, card.interval / 2)

        case .easy:
            // Recalled comfortably — reward EF, advance interval via SM-2
            card.easeFactor = max(Self.efMin, card.easeFactor + 0.10)
            switch card.repetitions {
            case 0:  card.interval = 1
            case 1:  card.interval = 6
            default: card.interval = max(1, Int((Double(card.interval) * card.easeFactor).rounded()))
            }
            card.repetitions += 1
        }

        // Schedule from start of today so the card becomes available
        // at midnight on the due day — not N×24h after the exact review time.
        let startOfToday = Calendar.current.startOfDay(for: now)
        card.dueDate = Calendar.current.date(
            byAdding: .day,
            value: card.interval,
            to: startOfToday
        ) ?? now
    }

    /// Applies SM-2 to `set`, mutating its SRS fields in place.
    /// The caller is responsible for saving the ModelContext afterwards.
    func evaluate(set: DynamicSet, rating: SRSRating) {
        let now = Date.now
        set.lastReviewed = now

        switch rating {

        case .again:
            set.easeFactor  = max(Self.efMin, set.easeFactor - 0.20)
            set.repetitions = 0
            set.interval    = 1

        case .hard:
            set.easeFactor = max(Self.efMin, set.easeFactor - 0.15)
            set.interval   = max(1, set.interval / 2)

        case .easy:
            set.easeFactor = max(Self.efMin, set.easeFactor + 0.10)
            switch set.repetitions {
            case 0:  set.interval = 1
            case 1:  set.interval = 6
            default: set.interval = max(1, Int((Double(set.interval) * set.easeFactor).rounded()))
            }
            set.repetitions += 1
        }

        let startOfToday = Calendar.current.startOfDay(for: now)
        set.dueDate = Calendar.current.date(
            byAdding: .day,
            value: set.interval,
            to: startOfToday
        ) ?? now
    }
}
