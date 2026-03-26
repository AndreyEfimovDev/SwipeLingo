import Foundation

// Common European Framework of Reference for Languages
enum CEFRLevel: String, CaseIterable, Codable {
    case a0a1 = "A0/A1"
    case a2   = "A2"
    case b1   = "B1"
    case b2   = "B2"
    case c1   = "C1"
    case c2   = "C2"

    var displayName: String {
        switch self {
        case .a0a1: return "Beginner"
        case .a2:   return "Pre-Intermediate"
        case .b1:   return "Intermediate"
        case .b2:   return "Upper-Intermediate"
        case .c1:   return "Advanced"
        case .c2:   return "Proficiency"
        }
    }
}
