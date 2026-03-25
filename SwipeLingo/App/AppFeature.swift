import SwiftUI

// MARK: - AppViewModel
//
// Injected into the environment so any descendant (e.g. PileBuilderView)
// can switch the active tab without needing a Binding chain.

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

    var body: some View {
        TabView(selection: Bindable(viewModel).selectedTab) {
            Tab("Study", systemImage: "rectangle.stack.fill", value: AppViewModel.AppTab.study) {
                StudyView()
            }
            Tab("Library", systemImage: "books.vertical.fill", value: AppViewModel.AppTab.library) {
                LibraryView()
            }
            Tab("Stats", systemImage: "chart.line.uptrend.xyaxis", value: AppViewModel.AppTab.statistics) {
                StatisticsView()
            }
            Tab("Settings", systemImage: "gear", value: AppViewModel.AppTab.preferences) {
                PreferencesView()
            }
        }
        .environment(viewModel)          // ← makes AppViewModel available everywhere
        .preferredColorScheme(preferredScheme)
    }

    private var preferredScheme: ColorScheme? {
        switch colorSchemeKey {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}
