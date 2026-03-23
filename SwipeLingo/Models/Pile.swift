import Foundation
import SwiftData

// cards is a computed property — not stored in the database.
// Resolved in service layer via:
//   sets.filter { setIds.contains($0.id) }
//       .flatMap { fetch Cards where setId == $0.id }
//       .filter { $0.status == .active }
@Model
final class Pile {
    var id: UUID
    var name: String
    var setIds: [UUID]
    var isActive: Bool
    var shuffleMethod: ShuffleMethod
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        setIds: [UUID] = [],
        isActive: Bool = false,
        shuffleMethod: ShuffleMethod = .random,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.setIds = setIds
        self.isActive = isActive
        self.shuffleMethod = shuffleMethod
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
