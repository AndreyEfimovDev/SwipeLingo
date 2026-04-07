import SwiftUI

// MARK: - AppViewModel

@Observable
final class AppViewModel {

    private static let studyModeKey = "studyMode"

    var studyMode: StudyMode {
        didSet { UserDefaults.standard.set(studyMode.rawValue, forKey: Self.studyModeKey) }
    }
    var activeSheet: AppSheet? = nil

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.studyModeKey) ?? ""
        studyMode = StudyMode(rawValue: saved) ?? .cards
    }

    // MARK: - StudyMode

    enum StudyMode: String {
        case cards
        case pairs

        var icon: String {
            switch self {
            case .cards: return "rectangle.stack"
            case .pairs: return "sparkles"
            }
        }

        var label: String {
            switch self {
            case .cards: return "Cards"
            case .pairs: return "Pairs"
            }
        }

        var other: StudyMode {
            switch self {
            case .cards: return .pairs
            case .pairs: return .cards
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

// MARK: - AppView

struct AppView: View {

    @State private var viewModel = AppViewModel()
    @AppStorage("colorScheme") private var theme: Theme = .system

    init() { configureNavigationBarAppearance() }

    var body: some View {
        studyContent
            .fullScreenCover(item: Bindable(viewModel).activeSheet) { sheet in
                sheetView(for: sheet)
            }
            .environment(viewModel)
            .preferredColorScheme(theme.colorScheme)
            .foregroundStyle(Color.myColors.myAccent)
            .errorAlert()
    }

    // MARK: - Study Content

    @ViewBuilder
    private var studyContent: some View {
        switch viewModel.studyMode {
        case .cards: FlashCardsView()
        case .pairs: DynamicCardsView()
        }
    }

    // MARK: - Full Screen Cover Content

    @ViewBuilder
    private func sheetView(for sheet: AppViewModel.AppSheet) -> some View {
        switch sheet {
        case .cardsLibrary: LibraryView()
        case .pairsLibrary: NavigationStack { PairsLibraryView() }
        case .statistics:   StatisticsView()
        case .settings:     SettingsView()
        }
    }

    // MARK: - UIKit Appearance

    private func configureNavigationBarAppearance() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithTransparentBackground()
        tabBarAppearance.backgroundColor = UIColor(Color.myColors.myBackground)
        let inactiveColor = UIColor(Color.myColors.myAccent).withAlphaComponent(0.5)
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor    = inactiveColor
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: inactiveColor]
        UITabBar.appearance().standardAppearance   = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(Color.myColors.myBackground)
        navBarAppearance.backgroundEffect = nil
        navBarAppearance.shadowColor = .clear

        let accentColor = UIColor(Color.myColors.myAccent)
        navBarAppearance.largeTitleTextAttributes = [
            .foregroundColor: accentColor,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: accentColor,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]

        UINavigationBar.appearance().standardAppearance         = navBarAppearance
        UINavigationBar.appearance().compactAppearance          = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance       = navBarAppearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = UIColor(named: "myBlue") ?? UIColor.systemBlue
        UITableView.appearance().backgroundColor = UIColor.clear
    }
}
