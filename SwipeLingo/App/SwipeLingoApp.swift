import SwiftUI
import SwiftData

@main
struct SwipeLingoApp: App {

    let container: ModelContainer

    init() {
        let schema = Schema([
            Card.self,
            CardSet.self,
            Collection.self,
            Pile.self,
            EnglishPlusCard.self
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
            print("[SwipeLingoApp] ⚠️ ModelContainer failed (\(error))")
            print("[SwipeLingoApp] 🗑 Deleting store at: \(storeURL.path)")
            Self.deleteStoreFiles(at: storeURL)

            do {
                container = try ModelContainer(for: schema, configurations: [config])
                print("[SwipeLingoApp] ✅ ModelContainer recreated after store reset")
            } catch {
                fatalError("[SwipeLingoApp] ModelContainer failed even after store reset: \(error)")
            }
        }

        MockDataSeeder.seedIfNeeded(into: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            AppView()
        }
        .modelContainer(container)
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
                print("[SwipeLingoApp]   not found: \(candidate.lastPathComponent)")
                continue
            }
            do {
                try fm.removeItem(at: candidate)
                print("[SwipeLingoApp]   deleted:   \(candidate.lastPathComponent)")
            } catch {
                print("[SwipeLingoApp]   ⚠️ could not delete \(candidate.lastPathComponent): \(error)")
            }
        }
    }
}
