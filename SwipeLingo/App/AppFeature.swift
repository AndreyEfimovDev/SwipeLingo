import SwiftUI

// MARK: - AppViewModel

@Observable
final class AppViewModel {
    var selectedTab: AppTab = .study

    enum AppTab {
        case study, library, preferences
    }
}

// MARK: - AppView

struct AppView: View {
    @State private var viewModel = AppViewModel()

    var body: some View {
        // Placeholder — will be replaced by TabView with
        // StudyViewModel, LibraryViewModel, PreferencesViewModel in Stage 2
        Text("SwipeLingo")
    }
}
