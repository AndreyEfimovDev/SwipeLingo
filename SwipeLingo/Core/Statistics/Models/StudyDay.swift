import Foundation
import SwiftData

// MARK: - StudyDay
//
// Счётчики занятий за один день на одном устройстве — история для Statistics, серии дней, виджета и
// напоминаний. У карточек хранится только дата последнего повторения, по ней историю не восстановить.
//
// Одна запись = (день, устройство, аккаунт). Каждое устройство увеличивает только свою запись, поэтому
// CloudKit не сталкивает конкурентные изменения одного счётчика с разных устройств; итог дня — сумма
// записей всех устройств аккаунта (считает сервис статистики). Владелец — тот же принцип, что
// `Collection.ownerFirebaseUID`: на общем iCloud статистика разных Firebase-аккаунтов не смешивается.
//
// CloudKit: все поля с default-значениями, без `unique` (требование CloudKit-синка SwiftData).

@Model
final class StudyDay {
    var id: UUID = UUID()
    /// День по местному времени устройства в формате `yyyy-MM-dd` (см. `StudyDay.dayKey(for:)`).
    var dayKey: String = ""
    /// Идентификатор устройства-автора записи (см. `StudyDevice.currentID`).
    var deviceID: String = ""
    /// Firebase UID владельца; пустая строка — запись без аккаунта (не ожидается: гость тоже имеет UID).
    var ownerFirebaseUID: String = ""

    /// Карточек просмотрено: любой свайп (выучил / оставил / удалил) или оценка SRS — одна карточка = одно действие.
    var cardsReviewed: Int = 0
    /// Карточек переведено в Learnt свайпом вправо.
    var cardsLearnt: Int = 0
    /// Оценки SRS карточек.
    var easyCount: Int = 0
    var hardCount: Int = 0
    var forgotCount: Int = 0
    /// Пройдено сетов Level Up (досмотрен до конца).
    var levelUpSetsCompleted: Int = 0

    var updatedAt: Date = Date.now

    init(dayKey: String, deviceID: String, ownerFirebaseUID: String) {
        self.id = UUID()
        self.dayKey = dayKey
        self.deviceID = deviceID
        self.ownerFirebaseUID = ownerFirebaseUID
        self.updatedAt = Date.now
    }

    /// Было ли в этой записи хоть одно занятие.
    var hasActivity: Bool { cardsReviewed > 0 || levelUpSetsCompleted > 0 }

    // MARK: - Day key

    /// Ключ дня по местному календарю: `yyyy-MM-dd`. Граница дня — полночь по времени устройства.
    /// Григорианский календарь задан явно, а строка собирается из чисел без локали: ключ не должен зависеть
    /// от настроек календаря и языка пользователя (иначе один и тот же день на двух устройствах получил бы
    /// разные ключи).
    /// - Parameters:
    ///   - date: момент времени.
    ///   - timeZone: часовой пояс; по умолчанию — текущий устройства.
    /// - Returns: ключ дня.
    static func dayKey(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
