import SwiftUI

// MARK: - AppViewModel

@Observable
final class AppViewModel {
    var selectedTab: AppTab = .study

    enum AppTab: Hashable {
        case study, library, statistics, preferences
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
        Group {
            if isLandscape {
                landscapeLayout
            } else {
                portraitTabView
            }
        }
        .environment(viewModel)
        .preferredColorScheme(theme.colorScheme)
        .foregroundStyle(Color.myColors.myAccent)
    }

    // MARK: - Configuration Methods
    
    private func configureNavigationBarAppearance() {
        
        // Remove tab bar separator line (configureWithTransparentBackground
        // clears the shadow automatically; backgroundColor restores white fill)
        let tabBarappearance = UITabBarAppearance()
        tabBarappearance.configureWithTransparentBackground()
        tabBarappearance.backgroundColor = UIColor(Color.myColors.myBackground)
        UITabBar.appearance().standardAppearance   = tabBarappearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarappearance

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithTransparentBackground()
        navBarAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        
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
        UINavigationBar.appearance().tintColor = accentColor
        UITableView.appearance().backgroundColor = UIColor.clear
    }

    // MARK: - Portrait: system TabView

    private var portraitTabView: some View {
        TabView(selection: Bindable(viewModel).selectedTab) {
            Tab("Study",    systemImage: "rectangle.stack.fill",      value: AppViewModel.AppTab.study)       { StudyView() }
            Tab("Library",  systemImage: "books.vertical.fill",       value: AppViewModel.AppTab.library)     { LibraryView() }
            Tab("Stats",    systemImage: "chart.line.uptrend.xyaxis", value: AppViewModel.AppTab.statistics)  { StatisticsView() }
            Tab("Settings", systemImage: "gear",                      value: AppViewModel.AppTab.preferences) { SettingsView() }
        }
        .toolbarBackground(.hidden, for: .tabBar)
    }

    // MARK: - Landscape: custom HStack layout (no TabView → no bottom bar)

    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            verticalTabBar
            Divider()
            currentTabContent
        }
    }

    @ViewBuilder
    private var currentTabContent: some View {
        switch viewModel.selectedTab {
        case .study:       StudyView()
        case .library:     LibraryView()
        case .statistics:  StatisticsView()
        case .preferences: SettingsView()
        }
    }

    // MARK: - Vertical Tab Bar

    private var verticalTabBar: some View {
        VStack(spacing: 0) {
            Spacer()
            tabBarItem(icon: "rectangle.stack.fill",      label: "Study",    tab: .study)
            Spacer()
            tabBarItem(icon: "books.vertical.fill",       label: "Library",  tab: .library)
            Spacer()
            tabBarItem(icon: "chart.line.uptrend.xyaxis", label: "Stats",    tab: .statistics)
            Spacer()
            tabBarItem(icon: "gear",                      label: "Settings", tab: .preferences)
            Spacer()
        }
        .frame(width: 56)
        // Background extends into leading safe area to fill the gap,
        // while icons stay within the safe area and are always visible.
        .background(Color.myColors.myBackground.ignoresSafeArea(edges: .leading))
    }

    @ViewBuilder
    private func tabBarItem(icon: String, label: String, tab: AppViewModel.AppTab) -> some View {
        let active = viewModel.selectedTab == tab
        Button { viewModel.selectedTab = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18))
                Text(label).font(.system(size: 9))
            }
            .foregroundStyle(active ? Color.accentColor : Color(.systemGray))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

}
