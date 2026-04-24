import SwiftUI
import SwiftData

// MARK: - AppView

struct AppView: View {

    @State private var viewModel = AppViewModel()
    @AppStorage("colorScheme") private var theme: Theme = .system
    @AppStorage("nativeLanguage") private var nativeLangRaw: String = ""
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    init() {
        configureNavigationBarAppearance()
    }

    var body: some View {
        studyContent
            .fullScreenCover(item: Bindable(viewModel).activeSheet) { sheet in
                sheetView(for: sheet)
            }
            .environment(viewModel)
            .preferredColorScheme(theme.colorScheme)
            .foregroundStyle(Color.myColors.myAccent)
            .errorAlert()
            .errorToast()
            // Re-sync when user changes CEFR level in Settings.
            // cefrLevelRaw is the stored String property — SwiftData observes it directly.
            .onChange(of: profiles.first?.cefrLevelRaw) { _, _ in
                let language = NativeLanguage(rawValue: nativeLangRaw) ?? .russian
                let level    = profiles.first?.cefrLevel ?? .c2
                Task {
                    await FirestoreImportService().syncFromFirestore(
                        into: context,
                        language: language,
                        upToLevel: level
                    )
                }
            }
    }

    // MARK: - Study Content

    @ViewBuilder
    private var studyContent: some View {
        switch viewModel.studyMode {
        case .cards: FlashCardsView()
        case .pairs: PairsView()
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
