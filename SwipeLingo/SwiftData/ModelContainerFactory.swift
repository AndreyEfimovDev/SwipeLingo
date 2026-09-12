import Foundation
import SwiftData

// MARK: - ModelContainerFactory
//
// Bootstrap SwiftData ModelContainer + CloudKit-backed store. Вынесен из
// SwipeLingoApp — это persistence-bootstrap, а не composition-root/routing
// забота точки входа.

enum ModelContainerFactory {

    /// Собирает `ModelContainer` приложения. При провале (например
    /// NSCocoaErrorDomain 134110 — schema mismatch) удаляет локальный стор и
    /// пересоздаёт контейнер один раз. Возвращает `nil`, только если пересоздание
    /// тоже не удалось.
    static func make() -> ModelContainer? {
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
            BookBookmark.self,
            AppSyncState.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        let storeURL = config.url

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
#warning("STUB: Replace with SchemaMigrationPlan before App Store release.")

            // NSCocoaErrorDomain Code=134110 → расхождение схемы.
            // TODO: заменить на SchemaMigrationPlan перед релизом в App Store.
            log("ModelContainer failed: \(error)", level: .error)
            log("🗑 Deleting store at: \(storeURL.path)", level: .warning)
            deleteStoreFiles(at: storeURL)

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

    // MARK: - Dev helper

    /// Удаляет SQLite-стор и сопутствующие ему WAL/SHM-файлы по указанному URL.
    ///
    /// SwiftData использует три файла на стор:
    ///   default.store        ← основная база данных
    ///   default.store-wal    ← write-ahead log
    ///   default.store-shm    ← shared-memory индекс
    ///
    /// Нужно удалить все три, иначе SQLite откажется открыть
    /// новый пустой стор, пока остаются осиротевшие WAL/SHM-файлы.
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
