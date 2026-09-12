import Foundation

// MARK: - SRS Rating

/// Оценка интервального повторения на три кнопки (отображается на значения качества SM-2).
enum SRSRating {
    case again  // Не знал — EF −0.20, полный сброс
    case hard   // Сложно  — EF −0.15, интервал не меняется
    case easy   // Легко   — EF +0.10, интервал увеличивается
}

// MARK: - SRSService

/// Реализует алгоритм интервального повторения SM-2.
/// Все мутации происходят напрямую на инстансе @Model Card.
/// Должен вызываться на том же акторе, что владеет ModelContext (по умолчанию MainActor).
struct SRSService {

    private static let efMin: Double = 1.3

    // MARK: - Public API

    /// Применяет SM-2 к `card`, мутируя её SRS-поля на месте.
    /// Вызывающая сторона отвечает за последующее сохранение ModelContext.
    func evaluate(card: Card, rating: SRSRating) {
        let now = Date.now
        card.lastReviewed = now

        switch rating {

        case .again:
            // Совсем забыл — штрафуем EF и сбрасываем серию
            card.easeFactor  = max(Self.efMin, card.easeFactor - 0.20)
            card.repetitions = 0
            card.interval    = 1

        case .hard:
            // Вспомнил с трудом — штрафуем EF, делим интервал пополам
            card.easeFactor = max(Self.efMin, card.easeFactor - 0.15)
            card.interval   = max(1, card.interval / 2)

        case .easy:
            // Вспомнил легко — вознаграждаем EF, увеличиваем интервал по SM-2
            card.easeFactor = max(Self.efMin, card.easeFactor + 0.10)
            switch card.repetitions {
            case 0:  card.interval = 1
            case 1:  card.interval = 6
            default: card.interval = max(1, Int((Double(card.interval) * card.easeFactor).rounded()))
            }
            card.repetitions += 1
        }

        // Планируем от начала сегодняшнего дня, чтобы карточка стала доступна
        // в полночь дня due — а не через N×24ч после точного момента оценки.
        let startOfToday = Calendar.current.startOfDay(for: now)
        card.dueDate = Calendar.current.date(
            byAdding: .day,
            value: card.interval,
            to: startOfToday
        ) ?? now
    }

    /// Применяет SM-2 к `set`, мутируя её SRS-поля на месте.
    /// Вызывающая сторона отвечает за последующее сохранение ModelContext.
    func evaluate(set: PairsSet, rating: SRSRating) {
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
