import SwiftUI
import SwiftData

// MARK: - AppView

struct AppView: View {

    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    /// Передаётся из composition root (SwipeLingoApp) — прокидывается дальше через init,
    /// не через .environment(), чтобы каждый потребитель был виден в сигнатуре явно.
    private let dependencies: AppDependencies
    private var vm: AppViewModel { dependencies.appViewModel }
    private var settings: AppSettings { dependencies.appSettings }
    /// Единственный источник правды — AppSyncStateService.nativeLanguage (SwiftData + CloudKit-синк);
    private var nativeLanguage: NativeLanguage { dependencies.appSyncStateService.nativeLanguage }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var body: some View {
        studyContent
            .fullScreenCover(item: Bindable(vm).activeSheet) { sheet in
                sheetView(for: sheet)
            }
            .preferredColorScheme(settings.theme.colorScheme)
            .foregroundStyle(Color.myColors.myAccent)
            .errorAlert()
            .errorBanner()
            .onChange(of: profiles.first?.cefrLevelRaw) { oldLevelRaw, newLevelRaw in
                vm.handleCEFRLevelChange(
                    oldRaw: oldLevelRaw,
                    newRaw: newLevelRaw,
                    nativeLanguage: nativeLanguage,
                    context: context
                )
            }
    }

    // MARK: - Study Content

    @ViewBuilder
    private var studyContent: some View {
        switch vm.studyMode {
        case .cards:
            CardsView(appViewModel: dependencies.appViewModel,
                            authService: dependencies.authFBService,
                            userService: dependencies.userFBService,
                            appSyncStateService: dependencies.appSyncStateService,
                            appSettings: dependencies.appSettings)
        case .pairs:
            PairsView(appViewModel: dependencies.appViewModel,
                       authService: dependencies.authFBService,
                       userService: dependencies.userFBService,
                       appSyncStateService: dependencies.appSyncStateService,
                       appSettings: dependencies.appSettings)
        case .books:
            BooksView(
                appViewModel: dependencies.appViewModel,
                appSyncStateService: dependencies.appSyncStateService,
                appSettings: dependencies.appSettings,
                userService: dependencies.userFBService
            )
        }
    }

    // MARK: - Full Screen Cover Content

    @ViewBuilder
    private func sheetView(for sheet: AppViewModel.AppSheet) -> some View {
        switch sheet {
        case .cardsLibrary:
            LibraryView(appViewModel: dependencies.appViewModel,
                        authService: dependencies.authFBService,
                        userService: dependencies.userFBService,
                        appSyncStateService: dependencies.appSyncStateService)
                .errorBanner()
        case .pairsLibrary:
            NavigationStack {
                PairsLibraryView(authService: dependencies.authFBService,
                                  userService: dependencies.userFBService,
                                  appSyncStateService: dependencies.appSyncStateService)
            }
            .errorBanner()
        case .statistics:
            StatisticsView()
        case .settings:
            SettingsView(syncState: dependencies.appSyncStateService,
                         authService: dependencies.authFBService,
                         userService: dependencies.userFBService,
                         appSettings: dependencies.appSettings)
        }
    }
}
