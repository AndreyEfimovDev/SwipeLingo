import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseCrashlytics
import GoogleSignIn
import FirebaseAuth

@main
struct SwipeLingoApp: App {

    @Environment(\.scenePhase) private var scenePhase
    
    @AppStorage(Constants.StorageKey.nativeLanguage) private var nativeLanguage: NativeLanguage = .russian

    let container: ModelContainer?

    @State private var authService: FireBaseAuthService
    @State private var userService: UserService
    @State private var appSyncStateService: AppSyncStateService
    @State private var appViewModel: AppViewModel

    /// Собирается заново на каждый body-evaluation — дёшево, поля просто
    /// переупаковывают уже существующие @State-инстансы (reference types),
    /// сами сервисы не пересоздаются.
    private var dependencies: AppDependencies {
        AppDependencies(
            authService: authService,
            userService: userService,
            appSyncStateService: appSyncStateService,
            appViewModel: appViewModel
        )
    }

    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        // Firebase must be configured before AuthService initializes Auth.auth()
        if FirebaseApp.app() == nil {
            if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
                FirebaseApp.configure()
                if let clientID = FirebaseApp.app()?.options.clientID {
                    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
                }
                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
                log("[Firebase] App configured", level: .info)
            } else {
                log("[Firebase] GoogleService-Info.plist not found — Firebase disabled", level: .warning)
            }
        }

        // Fresh install detection: UserDefaults is wiped on reinstall, Keychain is not.
        // If this is the first launch ever recorded, sign out any stale Keychain token
        // so the user goes through onboarding + auth from scratch.
        let launchedBefore = UserDefaults.standard.bool(forKey: Constants.StorageKey.appEverLaunched)
        if !launchedBefore {
            try? Auth.auth().signOut()
            UserDefaults.standard.set(true, forKey: Constants.StorageKey.appEverLaunched)
            log("[App] Fresh install detected — Keychain token cleared", level: .info)
        }

        _authService = State(initialValue: FireBaseAuthService())
        _userService = State(initialValue: UserService())
        _appViewModel = State(initialValue: AppViewModel())
        let builtContainer = ModelContainerFactory.make()
        container = builtContainer
        if let ctx = builtContainer?.mainContext {
            SystemSeeder.ensureSystemCollections(into: ctx)
            _appSyncStateService = State(initialValue: AppSyncStateService(modelContext: ctx))
        } else {
            _appSyncStateService = State(initialValue: AppSyncStateService(modelContext: ModelContext(try! ModelContainer(for: AppSyncState.self))))
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isLoading {
                    Color.myColors.myBackground.ignoresSafeArea()
                } else if let container {
                    if !authService.isAuthenticated {
                        // Auth first: Sign In / Sign Up / Continue as Guest
                        AuthView(showGuestOption: true, authService: authService)
                    } else if !appSyncStateService.hasCompletedOnboarding {
                        // New user: language + level selection (no auth step —
                        // auth already handled above, before onboarding starts).
                        OnboardingView {
                            appSyncStateService.hasCompletedOnboarding = true
                        }
                        .modelContainer(container)
                    } else {
                        AppView(dependencies: dependencies)
                            .modelContainer(container)
                    }
                } else {
                    databseErrorView
                }
            }
            // Syncs live Firestore content into SwiftData (idempotent via firestoreId).
            // Skip on first launch (onboarding not done yet — no UserProfile, level unknown).
            // On first launch the sync is triggered by .onChange below after onboarding.
            .task {
                if appSyncStateService.hasCompletedOnboarding { await firestoreSync() }
            }
            .onChange(of: appSyncStateService.hasCompletedOnboarding) { _, completed in
                if completed { Task { await firestoreSync() } }
            }
            .onChange(of: authService.currentUser) { _, user in
                if let user { AnalyticsService.setUser(id: user.uid) }
                else { AnalyticsService.clearUser() }
            }
        }
        // Single entry point for all Firestore writes after a verified session.
        // Fires on app launch (after verifySession passes) and after every fresh sign-in.
        .onChange(of: authService.isSessionVerified) { _, verified in
            guard verified, let user = authService.currentUser else { return }
            Task {
                let isReturningUser = await UserSessionSyncService().syncAfterVerifiedSession(
                    user: user, container: container, nativeLanguage: nativeLanguage, userService: userService
                )
                // Second device: Firebase doc exists with cefrLevel → skip onboarding
                if isReturningUser && !appSyncStateService.hasCompletedOnboarding {
                    appSyncStateService.hasCompletedOnboarding = true
                    log("[App] Returning user detected — skipping onboarding", level: .info)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if let container { InboxDrainService().drain(container: container) }
                // Re-sync subscription on each foreground to catch server-side changes.
                if let uid = authService.currentUser?.uid {
                    Task { await userService.syncSubscription(for: uid) }
                }
            }
        }
    }

    // MARK: - Database Error

    /// Shown when the SwiftData ModelContainer fails to initialize even after a store reset.
    /// Displayed instead of the main app content — no SwiftData dependency.
    private var databseErrorView: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Database Error")
                .font(.title.bold())

            Text("The app could not initialize its database.\nPlease reinstall the app.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Firestore sync

    private func firestoreSync() async {
        guard let ctx = container?.mainContext else { return }

        let language = nativeLanguage

        // Уровень пользователя из UserProfile — определяет какие сеты загружать
        let profiles  = ctx.fetchWithErrorHandling(FetchDescriptor<UserProfile>())
        let userLevel = profiles.first?.cefrLevel ?? .c2  // c2 = загрузить всё если профиль не задан

        await FirestoreImportService().syncFromFirestore(
            into: ctx,
            language: language,
            upToLevel: userLevel
        )
    }

}
