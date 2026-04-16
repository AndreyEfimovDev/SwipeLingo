import Foundation
import SwiftUI

// Common European Framework of Reference for Languages
enum CEFRLevel: String, CaseIterable, Codable {
    case a1
    case a2
    case b1
    case b2
    case c1
    case c2
    
    var displayCode: String {
        switch self {
        case .a1: return "A1"
        case .a2: return "A2"
        case .b1: return "B1"
        case .b2: return "B2"
        case .c1: return "C1"
        case .c2: return "C2"
        }
    }
    
    var displayName: String {
        switch self {
        case .a1: return "Beginner"
        case .a2: return "Pre-Intermediate"
        case .b1: return "Intermediate"
        case .b2: return "Upper-Intermediate"
        case .c1: return "Advanced"
        case .c2: return "Proficiency"
        }
    }

    var color: Color {
        #if os(iOS)
        switch self {
        case .a1: return Color.myColors.myGreen
        case .a2: return Color.myColors.myBlue
        case .b1: return Color.myColors.myYellow
        case .b2: return Color.myColors.myOrange
        case .c1: return Color.myColors.myPurple
        case .c2: return Color.myColors.myRed
        }
        #else
        switch self {
        case .a1: return .green
        case .a2: return .blue
        case .b1: return .yellow
        case .b2: return .orange
        case .c1: return .purple
        case .c2: return .red
        }
        #endif
    }
}
