import Foundation

// MARK: - Date sentinels
//
// Замена distantPast/distantFuture — гарантированно совместимы с Firebase Firestore.

extension Date {
    /// Sentinel «никогда не обновлялось» — Unix epoch, 1970-01-01.
    /// Используется в updatedAt, lastReviewed как значение по умолчанию.
    static let epoch = Date(timeIntervalSince1970: 0)

    /// Sentinel «ещё не наступил Due» — 2100-01-01.
    /// Используется в dueDate новых карточек/сетов до первой SRS-оценки.
    static let farFuture = Date(timeIntervalSince1970: 4_102_444_800)
}

// MARK: - DateFormatter

extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    static let yyyyMMddHHmm: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return formatter
    }()
}
