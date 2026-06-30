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
// Только один pile может быть isActive в каждый момент.

@Model
final class PairsPile {
    var id: UUID = UUID()
    var name: String = ""
    private var setIdsRaw: String = ""
    var shuffleMethodRaw: String = ShuffleMethod.random.rawValue
    var isActive: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var setIds: [UUID] {
        get { decodeUUIDs(setIdsRaw) }
        set { setIdsRaw = encodeUUIDs(newValue) }
    }

    var shuffleMethod: ShuffleMethod {
        get { ShuffleMethod(rawValue: shuffleMethodRaw) ?? .random }
        set { shuffleMethodRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        setIds: [UUID] = [],
        shuffleMethod: ShuffleMethod = .random,
        isActive: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id               = id
        self.name             = name
        self.setIdsRaw        = encodeUUIDs(setIds)
        self.shuffleMethodRaw = shuffleMethod.rawValue
        self.isActive         = isActive
        self.createdAt        = createdAt
        self.updatedAt        = updatedAt
    }
}
