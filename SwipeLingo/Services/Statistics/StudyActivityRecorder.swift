import Foundation
import SwiftData

// MARK: - StudyEvent

/// Действие пользователя, которое попадает в историю занятий (`StudyDay`).
enum StudyEvent: Equatable {
    /// Свайп карточки на лицевой стороне: вправо — выучил (`learnt: true`), влево — оставил учить.
    case cardSwiped(learnt: Bool)
    /// Свайп карточки вверх — удалить.
    case cardDeleted
    /// Оценка карточки на обороте.
    case cardRated(SRSRating)
    /// Сет Level Up досмотрен до конца.
    case levelUpSetCompleted
}

// MARK: - StudyActivityRecorder
//
// Записывает действия пользователя в счётчики сегодняшней записи `StudyDay` этого устройства и аккаунта
// (создаёт её при первом действии за день). Stateless-структура, как SRSService/PileManagementService:
// ModelContext передаётся на каждый вызов, сохраняет вызывающая сторона — тем же save, что и само действие
// (карточка и счётчик сохраняются вместе).

struct StudyActivityRecorder {

    /// Firebase UID текущего аккаунта — владелец записей.
    let firebaseUID: String
    /// Идентификатор этого устройства.
    let deviceID: String

    /// - Parameters:
    ///   - firebaseUID: UID текущего аккаунта (из AuthFBService на экране, который создаёт ViewModel).
    ///   - deviceID: идентификатор устройства; по умолчанию — `StudyDevice.currentID` (подменяется в тестах).
    init(firebaseUID: String, deviceID: String = StudyDevice.currentID) {
        self.firebaseUID = firebaseUID
        self.deviceID = deviceID
    }

    /// Увеличивает счётчики сегодняшней записи под событие. Контекст не сохраняет.
    /// - Parameters:
    ///   - event: действие пользователя.
    ///   - context: контекст SwiftData.
    ///   - now: момент действия (подменяется в тестах); от него берётся ключ дня.
    func record(_ event: StudyEvent, context: ModelContext, now: Date = .now) {
        let day = todayRecord(context: context, now: now)
        switch event {
        case .cardSwiped(let learnt):
            day.cardsReviewed += 1
            if learnt { day.cardsLearnt += 1 }
        case .cardDeleted:
            day.cardsReviewed += 1
        case .cardRated(let rating):
            day.cardsReviewed += 1
            switch rating {
            case .easy:  day.easyCount += 1
            case .hard:  day.hardCount += 1
            case .again: day.forgotCount += 1
            }
        case .levelUpSetCompleted:
            day.levelUpSetsCompleted += 1
        }
        day.updatedAt = now
    }

    // MARK: - Private

    /// Запись (день, устройство, аккаунт); создаётся, если её ещё нет. Фильтр — в Swift после fetch, а не
    /// `#Predicate` по строкам (известный SIGILL SwiftData); записей немного — по одной на день и устройство.
    /// Fetch видит и ещё не сохранённую вставку этого же контекста, так что второе действие за день
    /// до сохранения не создаст вторую запись.
    private func todayRecord(context: ModelContext, now: Date) -> StudyDay {
        let key = StudyDay.dayKey(for: now)
        let existing = context.fetchWithErrorHandling(FetchDescriptor<StudyDay>()).first {
            $0.dayKey == key && $0.deviceID == deviceID && $0.ownerFirebaseUID == firebaseUID
        }
        if let existing { return existing }
        let day = StudyDay(dayKey: key, deviceID: deviceID, ownerFirebaseUID: firebaseUID)
        context.insert(day)
        return day
    }
}

// MARK: - StudyDevice

/// Идентификатор устройства для записей `StudyDay`. Случайный UUID, создаётся при первом обращении и
/// хранится локально в UserDefaults (не синхронизируется — у каждого устройства свой). После
/// переустановки будет новый — старые записи остаются в истории под прежним id и по-прежнему суммируются.
enum StudyDevice {

    /// Ключ UserDefaults. Здесь, а не в `Constants.StorageKey`: `currentID` — nonisolated, а `Constants`
    /// изолирован MainActor (изоляция по умолчанию), обращение к нему отсюда не скомпилируется.
    nonisolated private static let storageKey = "studyDeviceID"

    /// Идентификатор этого устройства. `nonisolated`: читается как default-значение параметра
    /// (`StudyActivityRecorder.init`), а такие выражения вычисляются вне MainActor; UserDefaults потокобезопасен.
    nonisolated static var currentID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: storageKey), !id.isEmpty { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: storageKey)
        return id
    }
}
