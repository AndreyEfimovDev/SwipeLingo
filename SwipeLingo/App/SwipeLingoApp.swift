import SwiftUI
import SwiftData
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    return true
  }
}


@main
struct SwipeLingoApp: App {

    @Environment(\.scenePhase) private var scenePhase
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let appGroupID  = "group.PELSH.SwipeLingo"
    private let pendingKey  = "pendingInboxWords"

    let container: ModelContainer?
    
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        container = Self.makeContainer()
        if let ctx = container?.mainContext {
            FirestoreImportService().importIfNeeded(into: ctx)
            MockDataSeeder.ensureSystemCollections(into: ctx)
            MockDataSeeder.ensureMockDevCollection(into: ctx)
            MockDataSeeder.ensureMockPairsSets(into: ctx)
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
            UserProfile.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        let storeURL = config.url

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
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
            if let container {
                if hasCompletedOnboarding {
                    AppView()
                        .modelContainer(container)
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                    .modelContainer(container)
                }
            } else {
                DatabseErrorView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                drainInboxQueue()
            }
        }
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
