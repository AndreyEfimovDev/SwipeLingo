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
            /// Ре-синхронизация при повышении CEFR-уровня пользователя.
            /// При ПОНИЖЕНИИ уровня данные уже есть локально — UI фильтрует по уровню мгновенно, sync не нужен.
            /// При ПОВЫШЕНИИ — нужен forceFullSync: true чтобы скачать контент нового уровня.
            /// (delta-запрос не подойдёт: новые сеты могут иметь updatedAt < lastSyncAt и не попадут в delta.)
            .onChange(of: profiles.first?.cefrLevelRaw) { oldLevelRaw, newLevelRaw in
                let oldLevel = CEFRLevel(rawValue: oldLevelRaw ?? "") ?? .c2
                let newLevel = CEFRLevel(rawValue: newLevelRaw ?? "") ?? .c2
                guard newLevel > oldLevel else { return }   // понижение — sync не нужен
                let language = nativeLanguage
                Task {
                    await ImportFSService().syncFromFirestore(
                        into: context,
                        language: language,
                        upToLevel: newLevel,
                        forceFullSync: true
                    )
                }
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
