import SwiftUI
import SwiftData

// MARK: - AppViewModel

@Observable
final class AppViewModel {

    var studyMode: StudyMode {
        didSet {
            UserDefaults.standard.set(studyMode.label, forKey: Constants.StorageKey.studyMode)
        }
    }
    var activeSheet: AppSheet? = nil

    init() {
        let saved = UserDefaults.standard.string(forKey: Constants.StorageKey.studyMode) ?? ""
        studyMode = StudyMode.allCases.first { $0.label == saved } ?? .cards
    }

    // MARK: - StudyMode

    enum StudyMode: String, CaseIterable {
        case cards
        case pairs
        case books

        var icon: String {
            switch self {
            case .cards: return "rectangle.stack"
            case .pairs: return "sparkles"
            case .books: return "book.closed"
            }
        }

        var label: String {
            switch self {
            case .cards: return "Cards"
            case .pairs: return "Pairs"
            case .books: return "Books"
            }
        }

        var other: StudyMode {
            switch self {
            case .cards: return .pairs
            case .pairs: return .books
            case .books: return .cards
            }
        }
    }

    // MARK: - AppSheet

    enum AppSheet: String, Identifiable {
        case cardsLibrary
        case pairsLibrary
        case statistics
        case settings

        var id: String { rawValue }
    }
}

// MARK: - Theme

enum Theme: String, CaseIterable {
    case light
    case dark
    case system

    var displayName: String {
        switch self {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .system: return "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}

