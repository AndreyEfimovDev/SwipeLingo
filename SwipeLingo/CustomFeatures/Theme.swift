import SwiftUI

// MARK: - Theme

/// App colour-scheme preference stored in @AppStorage("colorScheme").
/// Raw String value is persisted; `.system` replaces the old "auto" key.
enum Theme: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
