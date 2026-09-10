import Foundation

// MARK: - SwipeLingoBackup
// Top-level export envelope written to JSON.

struct SwipeLingoBackup: Codable {
    let version: Int
    let exportedAt: Date
    let cardSets: [BackupCardSet]
    let pairsSRS: [BackupPairsSRS]   // SRS state only — content re-syncs from Firestore

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
    let firestoreId: String?   // fallback match key on restore
    let title: String?
    let cefrLevel: String
    let dueDate: Date
    let interval: Int
    let easeFactor: Double
    let repetitions: Int
    let lastReviewed: Date
}
