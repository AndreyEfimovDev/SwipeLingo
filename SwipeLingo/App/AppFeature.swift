import SwiftUI

// MARK: - AppViewModel

@Observable
final class AppViewModel {
    var selectedTab: AppTab = .study

    enum AppTab: Hashable {
        case study, library, statistics, preferences
    }
}

// MARK: - AppView

struct AppView: View {
    @State private var viewModel = AppViewModel()
    @AppStorage("colorScheme") private var colorSchemeKey = "auto"
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    init() {
        // Remove tab bar separator line (configureWithTransparentBackground
        // clears the shadow automatically; backgroundColor restores white fill)
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .systemBackground
        UITabBar.appearance().standardAppearance   = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
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
        .preferredColorScheme(preferredScheme)
    }

    // MARK: - Portrait: system TabView

    private var portraitTabView: some View {
        TabView(selection: Bindable(viewModel).selectedTab) {
            Tab("Study",    systemImage: "rectangle.stack.fill",      value: AppViewModel.AppTab.study)       { StudyView() }
            Tab("Library",  systemImage: "books.vertical.fill",       value: AppViewModel.AppTab.library)     { LibraryView() }
            Tab("Stats",    systemImage: "chart.line.uptrend.xyaxis", value: AppViewModel.AppTab.statistics)  { StatisticsView() }
            Tab("Settings", systemImage: "gear",                      value: AppViewModel.AppTab.preferences) { PreferencesView() }
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
        case .preferences: PreferencesView()
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
        .background(Color(.systemBackground).ignoresSafeArea(edges: .leading))
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

    // MARK: - Color scheme

    private var preferredScheme: ColorScheme? {
        switch colorSchemeKey {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}
