import SwiftUI

// MARK: - AppViewModel

@Observable
final class AppViewModel {

    private static let selectedTabKey = "selectedTab"

    var selectedTab: AppTab {
        didSet {
            UserDefaults.standard.set(selectedTab.rawValue, forKey: Self.selectedTabKey)
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.selectedTabKey) ?? ""
        selectedTab = AppTab(rawValue: saved) ?? .flashCards
    }

    enum AppTab: String, Hashable, CaseIterable {
        case flashCards
        case pairs
        case library
        case statistics
        case preferences

        var label: LocalizedStringKey {
            switch self {
            case .flashCards:   return "Cards"
            case .pairs:  return "Pairs"
            case .library:      return "Library"
            case .statistics:   return "Stats"
            case .preferences:  return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .flashCards:   return "rectangle.stack"
            case .pairs:  return "sparkles"
            case .library:      return "books.vertical"
            case .statistics:   return "chart.line.uptrend.xyaxis"
            case .preferences:  return "gear"
            }
        }
    }
}

enum Theme: String, CaseIterable {
    case light
    case dark
    case system
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}


// MARK: - AppView

struct AppView: View {
    
    @State private var viewModel = AppViewModel()
    @AppStorage("colorScheme") private var theme: Theme = .system
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    init() {
        configureNavigationBarAppearance()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                // Reserve space for the sidebar in landscape so content doesn't slide under it.
                if isLandscape { Color.clear.frame(width: 56) }

                TabView(selection: Bindable(viewModel).selectedTab) {
                    Tab(AppViewModel.AppTab.flashCards.label,
                        systemImage: AppViewModel.AppTab.flashCards.icon,
                        value: AppViewModel.AppTab.flashCards) {
                        FlashCardsView()
                            .toolbar(isLandscape ? .hidden : .automatic, for: .tabBar)
                    }
                    Tab(AppViewModel.AppTab.pairs.label,
                        systemImage: AppViewModel.AppTab.pairs.icon,
                        value: AppViewModel.AppTab.pairs) {
                        DynamicCardsView()
                            .toolbar(isLandscape ? .hidden : .automatic, for: .tabBar)
                    }
                    Tab(AppViewModel.AppTab.library.label,
                        systemImage: AppViewModel.AppTab.library.icon,
                        value: AppViewModel.AppTab.library) {
                        LibraryView()
                            .toolbar(isLandscape ? .hidden : .automatic, for: .tabBar)
                    }
                    Tab(AppViewModel.AppTab.statistics.label,
                        systemImage: AppViewModel.AppTab.statistics.icon,
                        value: AppViewModel.AppTab.statistics) {
                        StatisticsView()
                            .toolbar(isLandscape ? .hidden : .automatic, for: .tabBar)
                    }
                    Tab(AppViewModel.AppTab.preferences.label,
                        systemImage: AppViewModel.AppTab.preferences.icon,
                        value: AppViewModel.AppTab.preferences) {
                        SettingsView()
                            .toolbar(isLandscape ? .hidden : .automatic, for: .tabBar)
                    }
                }
                .toolbarBackground(.hidden, for: .tabBar)
            }

            if isLandscape { verticalTabBar }
        }
        .environment(viewModel)
        .preferredColorScheme(theme.colorScheme)
        .foregroundStyle(Color.myColors.myAccent)
        .errorAlert()
    }

    // MARK: - Configuration Methods
    
    private func configureNavigationBarAppearance() {
        
        // Remove tab bar separator line (configureWithTransparentBackground
        // clears the shadow automatically; backgroundColor restores white fill)
        let tabBarappearance = UITabBarAppearance()
        tabBarappearance.configureWithTransparentBackground()
        tabBarappearance.backgroundColor = UIColor(Color.myColors.myBackground)
        let inactiveColor = UIColor(Color.myColors.myAccent).withAlphaComponent(0.5)
        tabBarappearance.stackedLayoutAppearance.normal.iconColor    = inactiveColor
        tabBarappearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: inactiveColor]
        UITabBar.appearance().standardAppearance   = tabBarappearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarappearance

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
        
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = UIColor(named: "myBlue") ?? UIColor.systemBlue // системный back
        UITableView.appearance().backgroundColor = UIColor.clear
    }

    // MARK: - Vertical Tab Bar

    private var verticalTabBar: some View {
        VStack(spacing: 0) {
            ForEach(AppViewModel.AppTab.allCases, id: \.self) { tab in
                Spacer()
                tabBarItem(tab: tab)
            }
            Spacer()
        }
        .frame(width: 56)
        // Background extends into leading safe area to fill the gap,
        // while icons stay within the safe area and are always visible.
        .background(Color.myColors.myBackground.ignoresSafeArea(edges: .leading))
    }

    @ViewBuilder
    private func tabBarItem(tab: AppViewModel.AppTab) -> some View {
        let active = viewModel.selectedTab == tab
        Button { viewModel.selectedTab = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon).font(.system(size: 18))
                Text(tab.label).font(.system(size: 9))
            }
            .foregroundStyle(active ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

}
