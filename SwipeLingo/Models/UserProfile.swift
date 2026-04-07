import Foundation
import SwiftData

@Model
final class UserProfile {
    var name:         String = ""
    var cefrLevelRaw: String = CEFRLevel.a0a1.rawValue

    var cefrLevel: CEFRLevel {
        get { CEFRLevel(rawValue: cefrLevelRaw) ?? .a0a1 }
        set { cefrLevelRaw = newValue.rawValue }
    }

    /// Отображаемое имя: "Anonymous" если name пустое
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Anonymous" : trimmed
    }

    init(name: String = "", level: CEFRLevel = .a0a1) {
        self.name         = name
        self.cefrLevelRaw = level.rawValue
    }
}
