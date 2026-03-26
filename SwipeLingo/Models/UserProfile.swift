import Foundation
import SwiftData

@Model
final class UserProfile {
    var cefrLevelRaw: String = CEFRLevel.a0a1.rawValue

    var cefrLevel: CEFRLevel {
        get { CEFRLevel(rawValue: cefrLevelRaw) ?? .a0a1 }
        set { cefrLevelRaw = newValue.rawValue }
    }

    init(level: CEFRLevel = .a0a1) {
        self.cefrLevelRaw = level.rawValue
    }
}
