import Foundation
import SwiftData

// EnglishPlusCard data model is in design.
// See PRD.md section 15 (Open Questions) and section 7.2 (English+ Dynamic Cards).
// Fields will be added once the content type structure is finalized.
@Model
final class EnglishPlusCard {
    var id: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        createdAt: Date = .now
    ) {
        self.id = id
        self.createdAt = createdAt
    }
}
