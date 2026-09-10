import Foundation
import SwiftData

// MARK: - UUID array helpers
//
// SwiftData + CloudKit cannot materialise Array<UUID>.
// Same pattern as Card's [String] fields: persist as a
// U+001F-delimited String of uuidString values.

private let kUUIDSep = "\u{001F}"

private func encodeUUIDs(_ ids: [UUID]) -> String {
    ids.map { $0.uuidString }.joined(separator: kUUIDSep)
}

private func decodeUUIDs(_ raw: String) -> [UUID] {
    guard !raw.isEmpty else { return [] }
    return raw.components(separatedBy: kUUIDSep).compactMap { UUID(uuidString: $0) }
}

// MARK: - Pile

// cards is a computed property — not stored in the database.
// Resolved in service layer via:
//   sets.filter { setIds.contains($0.id) }
//       .flatMap { fetch Cards where setId == $0.id }
//       .filter { $0.status == .active }

@Model
final class Pile {
    var id: UUID = UUID()
    var name: String = ""
    /// Backing store — plain String is CloudKit-compatible.
    private var setIdsRaw: String = ""
    var isActive: Bool = false
    var shuffleMethodRaw: String = ShuffleMethod.random.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: Computed [UUID] accessor

    var setIds: [UUID] {
        get { decodeUUIDs(setIdsRaw) }
        set { setIdsRaw = encodeUUIDs(newValue) }
    }

    var shuffleMethod: ShuffleMethod {
        get { ShuffleMethod(rawValue: shuffleMethodRaw) ?? .random }
        set { shuffleMethodRaw = newValue.rawValue }
    }

    // MARK: Init

    init(
        id: UUID = UUID(),
        name: String,
        setIds: [UUID] = [],
        isActive: Bool = false,
        shuffleMethod: ShuffleMethod = .random,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id           = id
        self.name         = name
        self.setIdsRaw    = encodeUUIDs(setIds)
        self.isActive         = isActive
        self.shuffleMethodRaw = shuffleMethod.rawValue
        self.createdAt        = createdAt
        self.updatedAt    = updatedAt
    }
}
