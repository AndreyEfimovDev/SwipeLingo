import Foundation
import SwiftData

// MARK: - UUID helpers (same pattern as Pile)

private let kUUIDSep = "\u{001F}"

private func encodeUUIDs(_ ids: [UUID]) -> String {
    ids.map { $0.uuidString }.joined(separator: kUUIDSep)
}

private func decodeUUIDs(_ raw: String) -> [UUID] {
    guard !raw.isEmpty else { return [] }
    return raw.components(separatedBy: kUUIDSep).compactMap { UUID(uuidString: $0) }
}

// MARK: - PairsPile
// Именованная подборка PairsSet-ов для раздела Pairs.
// Без shuffleMethod — сеты воспроизводятся в заданном порядке.
// Только один pile может быть isActive в каждый момент.

@Model
final class PairsPile {
    var id: UUID
    var name: String
    private var setIdsRaw: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    var setIds: [UUID] {
        get { decodeUUIDs(setIdsRaw) }
        set { setIdsRaw = encodeUUIDs(newValue) }
    }

    init(
        id: UUID = UUID(),
        name: String,
        setIds: [UUID] = [],
        isActive: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id         = id
        self.name       = name
        self.setIdsRaw  = encodeUUIDs(setIds)
        self.isActive   = isActive
        self.createdAt  = createdAt
        self.updatedAt  = updatedAt
    }
}
