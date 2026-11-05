import Foundation

// MARK: - SwipeLingoBackup
// Верхнеуровневый конверт экспорта, записывается в JSON.

struct SwipeLingoBackup: Codable {
    let version: Int
    let exportedAt: Date
    let cardSets: [BackupCardSet]
    let pairsSRS: [BackupPairsSRS]   // только SRS-состояние — контент пересинхронизируется из Firestore

    init(cardSets: [BackupCardSet], pairsSRS: [BackupPairsSRS]) {
        self.version    = 1
        self.exportedAt = .now
        self.cardSets   = cardSets
        self.pairsSRS   = pairsSRS
    }
}

// MARK: - Cards

struct BackupCardSet: Codable {
    let id: UUID
    let name: String
    /// Сет — Inbox (лежит в системной коллекции). При восстановлении его карточки добавляются
    /// в текущий Inbox, отдельный сет не создаётся (после переустановки у Inbox другой id).
    let isInbox: Bool
    /// Название коллекции сета — при восстановлении сет попадает в свою коллекцию с этим названием
    /// (создаётся, если её нет). Для Inbox не используется.
    let collectionName: String
    /// Иконка коллекции (SF Symbol) — для создаваемой при восстановлении коллекции.
    let collectionIcon: String?
    let level: String
    let setDescription: String?
    let createdAt: Date
    let cards: [BackupCard]
}

struct BackupCard: Codable {
    let id: UUID
    let en: String
    let item: String
    let sampleEN: [String]
    let sampleItem: [String]
    let userSampleEN: [String]
    let userSampleItem: [String]
    let status: String
    let isFavorite: Bool
    let tags: [String]
    let synonyms: [String]
    let level: String
    // SRS state
    let easeFactor: Double
    let interval: Int
    let repetitions: Int
    let dueDate: Date
    let lastReviewed: Date
    let createdAt: Date
}

// MARK: - Pairs SRS

struct BackupPairsSRS: Codable {
    let id: UUID
    let firestoreId: String?   // резервный ключ сопоставления при восстановлении
    let title: String?
    let cefrLevel: String
    let dueDate: Date
    let interval: Int
    let easeFactor: Double
    let repetitions: Int
    let lastReviewed: Date
}
