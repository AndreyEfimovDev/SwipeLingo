import SwiftUI

// MARK: - AppViewModel

@Observable
final class AppViewModel {
    var selectedTab: AppTab = .study

    enum AppTab: Hashable {
        case study, library, preferences
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
            Tab("Settings", systemImage: "gear", value: AppViewModel.AppTab.preferences) {
                PreferencesView()
            }
        }
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
