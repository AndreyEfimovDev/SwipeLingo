import SwiftUI
import SwiftData

@main
struct SwipeLingoApp: App {

    @Environment(\.scenePhase) private var scenePhase

    private let appGroupID  = "group.PELSH.SwipeLingo"
    private let pendingKey  = "pendingInboxWords"

    let container: ModelContainer

    init() {
        let schema = Schema([
            Card.self,
            CardSet.self,
            Collection.self,
            Pile.self,
            EnglishPlusCard.self,
            UserProfile.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        // config.url is resolved by SwiftData at construction time —
        // before the container even tries to open the store.
        // We use it to target the exact files on recovery.
        let storeURL = config.url

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // NSCocoaErrorDomain Code=134110 → schema mismatch / loadIssueModelContainer.
            // During development the schema changes often; wipe the store and start fresh.
            // TODO: Replace with SchemaMigrationPlan before App Store release.
            log("ModelContainer failed: \(error)", level: .error)
            log("🗑 Deleting store at: \(storeURL.path)", level: .warning)
            Self.deleteStoreFiles(at: storeURL)

            do {
                container = try ModelContainer(for: schema, configurations: [config])
                log("ModelContainer recreated after store reset", level: .info)
            } catch {
                fatalError("[SwipeLingoApp] ModelContainer failed even after store reset: \(error)")
            }
        }

        FirestoreImportService().importIfNeeded(into: container.mainContext)
        MockDataSeeder.ensureSystemCollections(into: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            AppView()
        }
        .modelContainer(container)
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

        let context = ModelContext(container)

        // Resolve the Inbox CardSet — it is guaranteed to exist after
        // MockDataSeeder runs, but guard defensively.
        let allSets = (try? context.fetch(FetchDescriptor<CardSet>())) ?? []
        guard let inboxSet = allSets.first(where: { $0.name == "Inbox" }) else {
            log("[InboxDrain] Inbox CardSet not found — re-queuing \(pending.count) word(s)", level: .warning)
            var current = defaults?.stringArray(forKey: pendingKey) ?? []
            current.insert(contentsOf: pending, at: 0)
            defaults?.set(current, forKey: pendingKey)
            return
        }

        for word in pending {
            let card = Card(en: word, item: "", setId: inboxSet.id)
            context.insert(card)
            log("[InboxDrain] inserted '\(word)' → Inbox")
        }

        do {
            try context.save()
            log("[InboxDrain] saved \(pending.count) card(s) to Inbox", level: .info)
        } catch {
            log("[InboxDrain] save failed: \(error)", level: .error)
        }
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
