import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseCrashlytics
import GoogleSignIn
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}


@main
struct SwipeLingoApp: App {

    @Environment(\.scenePhase) private var scenePhase
    
    @AppStorage(Constants.StorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    private let appGroupID  = "group.PELSH.SwipeLingo"
    private let pendingKey  = "pendingInboxWords"

    let container: ModelContainer?

    @State private var authService: AuthService
    @State private var userService: UserService

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

        _authService = State(initialValue: AuthService())
        _userService = State(initialValue: UserService())
        container = Self.makeContainer()
        if let ctx = container?.mainContext {
            SystemSeeder.ensureSystemCollections(into: ctx)
        }
    }

    private static func makeContainer() -> ModelContainer? {
        let schema = Schema([
            Card.self,
            CardSet.self,
            Collection.self,
            Pile.self,
            PairsSet.self,
            PairsPile.self,
            UserProfile.self,
            Book.self,
            BookProgress.self,
            BookBookmark.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        let storeURL = config.url

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
#warning("STUB: Replace with SchemaMigrationPlan before App Store release.")

            // NSCocoaErrorDomain Code=134110 → schema mismatch.
            // TODO: Replace with SchemaMigrationPlan before App Store release.
            log("ModelContainer failed: \(error)", level: .error)
            log("🗑 Deleting store at: \(storeURL.path)", level: .warning)
            Self.deleteStoreFiles(at: storeURL)

            do {
                let container = try ModelContainer(for: schema, configurations: [config])
                log("ModelContainer recreated after store reset", level: .info)
                return container
            } catch {
                log("❌ ModelContainer failed even after store reset: \(error)", level: .error)
                ErrorManager.shared.handle(error, message: SwiftDataError.initializationFailed.message)
                return nil
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isLoading {
                    Color.myColors.myBackground.ignoresSafeArea()
                } else if let container {
                    if !hasCompletedOnboarding {
                        // Onboarding handles auth internally (step 4)
                        OnboardingView {
                            hasCompletedOnboarding = true
                        }
                        .modelContainer(container)
                        .environment(authService)
                        .environment(userService)
                    } else if !authService.isAuthenticated {
                        // Signed out after onboarding → standalone auth screen
                        AuthView()
                            .environment(authService)
                            .environment(userService)
                    } else {
                        AppView()
                            .modelContainer(container)
                            .environment(authService)
                            .environment(userService)
                    }
                } else {
                    DatabseErrorView()
                }
            }
            // Syncs live Firestore content into SwiftData (idempotent via firestoreId).
            // Skip on first launch (onboarding not done yet — no UserProfile, level unknown).
            // On first launch the sync is triggered by .onChange below after onboarding.
            .task {
                if hasCompletedOnboarding { await firestoreSync() }
            }
            // After onboarding: UserProfile exists with correct cefrLevel → sync with right level.
            .onChange(of: hasCompletedOnboarding) { _, completed in
                if completed {
                    Task { await firestoreSync() }
                }
            }
            // Create/update Firestore user doc on sign-in; sync subscription from Firestore.
            .onChange(of: authService.currentUser) { _, user in
                if let user {
                    AnalyticsService.setUser(id: user.uid)
                } else {
                    AnalyticsService.clearUser()
                }
                guard let user else { return }
                Task {
                    let langRaw = UserDefaults.standard.string(forKey: Constants.StorageKey.nativeLanguage) ?? ""
                    let ctx = container?.mainContext
                    let profiles = ctx?.fetchWithErrorHandling(FetchDescriptor<UserProfile>()) ?? []
                    let cefrRaw = profiles.first?.cefrLevel.rawValue ?? ""
                    await userService.createOrUpdateUser(user, nativeLanguage: langRaw, cefrLevel: cefrRaw)
                    await userService.syncSubscription(for: user.uid)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                drainInboxQueue()
                // Re-sync subscription on each foreground to catch server-side changes.
                if let uid = authService.currentUser?.uid {
                    Task { await userService.syncSubscription(for: uid) }
                }
            }
        }
    }

    // MARK: - Firestore sync

    private func firestoreSync() async {
        guard let ctx = container?.mainContext else { return }

        let langRaw  = UserDefaults.standard.string(forKey: "nativeLanguage") ?? ""
        let language = NativeLanguage(rawValue: langRaw) ?? .russian

        // Уровень пользователя из UserProfile — определяет какие сеты загружать
        let profiles  = ctx.fetchWithErrorHandling(FetchDescriptor<UserProfile>())
        let userLevel = profiles.first?.cefrLevel ?? .c2  // c2 = загрузить всё если профиль не задан

        await FirestoreImportService().syncFromFirestore(
            into: ctx,
            language: language,
            upToLevel: userLevel
        )
    }

    // MARK: - Share Extension inbox drain

    /// Reads words queued by the Share Extension from the shared App Group
    /// UserDefaults and inserts them as Cards into the Inbox CardSet.
    private func drainInboxQueue() {
        let defaults = UserDefaults(suiteName: appGroupID)
        guard
            let pending = defaults?.stringArray(forKey: pendingKey),
            !pending.isEmpty
        else { return }

        // Clear the queue immediately so a second foreground transition can't
        // re-import the same words if SwiftData save is slow.
        defaults?.removeObject(forKey: pendingKey)

        guard let container else { return }
        let context = ModelContext(container)

        // Resolve the Inbox CardSet — it is guaranteed to exist after
        // MockDataSeeder runs, but guard defensively.
        let allSets = context.fetchWithErrorHandling(FetchDescriptor<CardSet>())
        guard let inboxSet = allSets.first(where: { $0.name == "Inbox" }) else {
            log("[InboxDrain] Inbox CardSet not found — re-queuing \(pending.count) word(s)", level: .warning)
            var current = defaults?.stringArray(forKey: pendingKey) ?? []
            current.insert(contentsOf: pending, at: 0)
            defaults?.set(current, forKey: pendingKey)
            return
        }

        let inboxSetId = inboxSet.id
        let existingCards = context.fetchWithErrorHandling(
            FetchDescriptor<Card>(predicate: #Predicate { $0.setId == inboxSetId })
        )

        for word in pending {
            let wordLower = word.lowercased()
            guard !existingCards.contains(where: { $0.en.lowercased() == wordLower }) else {
                log("[InboxDrain] skipped duplicate '\(word)'", level: .info)
                continue
            }
            let card = Card(en: word, item: "", setId: inboxSet.id)
            context.insert(card)
            log("[InboxDrain] inserted '\(word)' → Inbox")
        }

        context.saveWithErrorHandling()
        AnalyticsService.wordSavedFromShareExtension(wordCount: pending.count)
        log("[InboxDrain] saved \(pending.count) card(s) to Inbox", level: .info)
    }

    // MARK: - Dev helper

    /// Deletes the SQLite store and its WAL/SHM siblings at the given URL.
    ///
    /// SwiftData uses three files per store:
    ///   default.store        ← main database
    ///   default.store-wal    ← write-ahead log
    ///   default.store-shm    ← shared-memory index
    ///
    /// We must remove all three, otherwise SQLite refuses to open
    /// a new empty store when orphaned WAL/SHM files still exist.
    private static func deleteStoreFiles(at storeURL: URL) {
        let fm   = FileManager.default
        let base = storeURL.deletingPathExtension()      // …/default
        let ext  = storeURL.pathExtension                // "store"

        for suffix in ["", "-wal", "-shm"] {
            let candidate = base.appendingPathExtension(ext + suffix)
            guard fm.fileExists(atPath: candidate.path) else {
                log("not found: \(candidate.lastPathComponent)")
                continue
            }
            do {
                try fm.removeItem(at: candidate)
                log("deleted: \(candidate.lastPathComponent)", level: .info)
            } catch {
                log("could not delete \(candidate.lastPathComponent): \(error)", level: .warning)
            }
        }
    }
}
