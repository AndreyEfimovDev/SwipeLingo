import Foundation
import SwiftData

// MARK: - ModelContainerFactory
//
// Bootstrap SwiftData ModelContainer + CloudKit-backed store. Вынесен из
// SwipeLingoApp — это persistence-bootstrap, а не composition-root/routing
// забота точки входа.

enum ModelContainerFactory {

    /// Собирает `ModelContainer` приложения — схема и переходы между её версиями
    /// берутся из `SwipeLingoMigrationPlan` (см. `SwipeLingoMigrationPlan.swift`),
    /// так что совместимые изменения схемы (новое поле с default-значением и т.п.)
    /// проходят через настоящую миграцию, без потери локальных данных.
    /// Удаление и пересоздание стора — только последний рубеж на случай, если
    /// миграция всё же не прошла (не ожидается в норме, но без неё сбой схемы
    /// оставил бы пользователя с нерабочим приложением без самостоятельного
    /// выхода). Возвращает `nil`, только если и это не помогло.
    static func make() -> ModelContainer? {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        let storeURL = config.url

        do {
            return try ModelContainer(for: schema, migrationPlan: SwipeLingoMigrationPlan.self, configurations: [config])
        } catch {
            log("ModelContainer failed: \(error)", level: .error)
            log("🗑 Deleting store at: \(storeURL.path)", level: .warning)
            deleteStoreFiles(at: storeURL)

            do {
                let container = try ModelContainer(for: schema, migrationPlan: SwipeLingoMigrationPlan.self, configurations: [config])
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
