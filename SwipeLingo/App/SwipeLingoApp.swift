import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseCrashlytics
import GoogleSignIn
import FirebaseAuth

@main
struct SwipeLingoApp: App {
    /// читаем системное состояние сцены (.active/.background/.inactive), нужно ниже для повторной синхронизации при возврате в foreground.
    @Environment(\.scenePhase) private var scenePhase

    /// родной язык пользователя, читается прямо из UserDefaults по ключу Constants.StorageKey.nativeLanguage. Обрати внимание: это не тот же источник правды, что AppSyncStateService.nativeLanguageRaw (см. ниже) — тот пишет в тот же ключ UserDefaults параллельно с CloudKit-записью, так что оба значения синхронизированы
    @AppStorage(Constants.StorageKey.nativeLanguage) private var nativeLanguage: NativeLanguage = .russian

    private let startup: Startup

    private enum Startup {
        case ready(container: ModelContainer, dependencies: AppDependencies)
        case failed
    }

    /// Подключает AppDelegate (CloudKit push, Google Sign-In URL handling) к жизненному циклу SwiftUI-приложения
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        /// Firebase необходимо настроить до того, как AuthService инициализирует Auth.auth().
        if FirebaseApp.app() == nil {
            if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
                FirebaseApp.configure()
                if let clientID = FirebaseApp.app()?.options.clientID {
                    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
                }
                // В DEBUG крашлитика отключена — тестовые креши из симулятора/отладки не должны засорять прод-дашборд.
                #if DEBUG
                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
                #else
                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
                #endif
                log("App configured", level: .info)
            } else {
                log("GoogleService-Info.plist not found — Firebase disabled", level: .warning)
            }
        }

        // Определение чистой установки: при переустановке UserDefaults очищается, а Keychain — нет.
        // Если это самый первый запуск, удаляем устаревший токен из Keychain,
        // чтобы пользователь заново прошел онбординг и аутентификацию.
        let launchedBefore = UserDefaults.standard.bool(forKey: Constants.StorageKey.appEverLaunched)
        if !launchedBefore {
            try? Auth.auth().signOut()
            UserDefaults.standard.set(true, forKey: Constants.StorageKey.appEverLaunched)
            log("Fresh install detected — Keychain token cleared", level: .info)
        }

        if let container = ModelContainerFactory.make() {
            SystemSeeder.ensureSystemCollections(into: container.mainContext)
            let dependencies = AppDependencies(
                authFBService: AuthFBService(),
                userFBService: UserFBService(),
                appSyncStateService: AppSyncStateService(modelContext: container.mainContext),
                appViewModel: AppViewModel()
            )
            startup = .ready(container: container, dependencies: dependencies)
        } else {
            startup = .failed
        }
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case .ready(let container, let dependencies):
                readyContent(container: container, dependencies: dependencies)
            case .failed:
                DatabaseErrorView()
            }
        }
    }

    // MARK: - Ready content

    /// Экран авторизации/онбординга/приложения плюс все side-effect подписки
    /// (Firestore sync, аналитика, foreground-триггеры). Вынесен из body
    /// отдельной функцией, потому что доступен только внутри .ready-ветки
    /// Startup — там, где есть реальный container и dependencies.
    @ViewBuilder
    private func readyContent(
        container: ModelContainer,
        dependencies: AppDependencies
    ) -> some View {
        let authService = dependencies.authFBService
        let appSyncStateService = dependencies.appSyncStateService
        let userService = dependencies.userFBService

        Group {
            if authService.isLoading {
                Color.myColors.myBackground.ignoresSafeArea()
                    .overlay { ProgressView() }
            } else if !authService.isAuthenticated {
                /// Авторизация: Войти / Зарегистрироваться / Продолжить как гость
                AuthView(showGuestOption: true, authService: authService)
            } else if !appSyncStateService.hasCompletedOnboarding {
                /// Новый пользователь: выбор языка и уровня (без этапа аутентификации —
                /// аутентификация уже выполнена выше, до начала онбординга).
                OnboardingView {
                    appSyncStateService.hasCompletedOnboarding = true
                }
                .modelContainer(container)
            } else {
                AppView(dependencies: dependencies)
                    .modelContainer(container)
            }
        }
        /// Синхронизирует актуальные данные из Firestore в SwiftData (операция идемпотентна благодаря firestoreId).
        /// Пропускается при первом запуске (онбординг еще не пройден: отсутствует UserProfile, уровень неизвестен).
        /// При первом запуске синхронизация инициируется ниже, в блоке .onChange, после завершения онбординга.
        .task {
            if appSyncStateService.hasCompletedOnboarding {
                await ImportFSService().syncForCurrentUser(container: container, language: nativeLanguage)
            }
        }
        .onChange(of: appSyncStateService.hasCompletedOnboarding) { _, completed in
            if completed {
                Task { await ImportFSService().syncForCurrentUser(container: container, language: nativeLanguage) }
            }
        }
        .onChange(of: authService.currentUser) { _, user in
            if let user {
                AnalyticsFBService.setUser(id: user.uid)
            } else {
                AnalyticsFBService.clearUser()
            }
        }
        /// Единая точка входа для всех операций записи в Firestore после подтверждения сеанса.
        /// Срабатывает при запуске приложения (после успешной проверки сеанса) и после каждого нового входа в систему.
        .onChange(of: authService.isSessionVerified) { _, verified in
            guard verified, let user = authService.currentUser else { return }
            Task {
                let isReturningUser = await UserSessionSyncService().syncAfterVerifiedSession(
                    user: user, container: container, nativeLanguage: nativeLanguage, userService: userService
                )
                // Второе устройство: документ Firebase уже содержит cefrLevel → пропускаем онбординг
                if isReturningUser && !appSyncStateService.hasCompletedOnboarding {
                    appSyncStateService.hasCompletedOnboarding = true
                    log("Returning user detected — skipping onboarding", level: .info)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                InboxDrainService().drain(container: container)
                /// Повторно синхронизировать подписку при каждом переходе приложения на передний план, чтобы получить изменения со стороны сервера.
                if let uid = authService.currentUser?.uid {
                    Task { await userService.syncSubscription(for: uid) }
                }
            }
        }
    }

}
