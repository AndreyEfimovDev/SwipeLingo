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

    /// опциональный, потому что бывает, что SwiftData вообще не поднимается (см. databseErrorView)
    let container: ModelContainer?

    /// composition root: FireBaseAuthService, FBUserService, AppSyncStateService, AppViewModel создаются один раз здесь и больше нигде. @State в App-структуре — валидный способ держать reference-type с identity, переживающей re-init структуры SwipeLingoApp (SwiftUI пересоздаёт саму struct на каждый re-render, но @State-storage персистентен)
    @State private var authService: AuthFBService
    @State private var userService: UserFBService
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

    /// Зарегистрировать делегат приложения для настройки Firebase
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
                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
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

        _authService = State(initialValue: AuthFBService())
        _userService = State(initialValue: UserFBService())
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
                } else {
                    databseErrorView
                }
            }
            /// Синхронизирует актуальные данные из Firestore в SwiftData (операция идемпотентна благодаря firestoreId).
            /// Пропускается при первом запуске (онбординг еще не пройден: отсутствует UserProfile, уровень неизвестен).
            /// При первом запуске синхронизация инициируется ниже, в блоке .onChange, после завершения онбординга.
            .task {
                if appSyncStateService.hasCompletedOnboarding { await firestoreSync() }
            }
            .onChange(of: appSyncStateService.hasCompletedOnboarding) { _, completed in
                if completed {
                    Task { await firestoreSync() }
                }
            }
            .onChange(of: authService.currentUser) { _, user in
                if let user {
                    AnalyticsFBService.setUser(id: user.uid)
                } else {
                    AnalyticsFBService.clearUser()
                }
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
                // Second device: Firebase doc exists with cefrLevel → skip onboarding
                if isReturningUser && !appSyncStateService.hasCompletedOnboarding {
                    appSyncStateService.hasCompletedOnboarding = true
                    log("Returning user detected — skipping onboarding", level: .info)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if let container {
                    InboxDrainService().drain(container: container)
                }
                /// Повторно синхронизировать подписку при каждом переходе приложения на передний план, чтобы получить изменения со стороны сервера.
                if let uid = authService.currentUser?.uid {
                    Task { await userService.syncSubscription(for: uid) }
                }
            }
        }
    }

    // MARK: - Database Error

    /// Отображается, если инициализация SwiftData ModelContainer не удается даже после сброса хранилища.
    /// Отображается вместо основного содержимого приложения — без зависимости от SwiftData..
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

        await ImportFSService().syncFromFirestore(
            into: ctx,
            language: language,
            upToLevel: userLevel
        )
    }

}
