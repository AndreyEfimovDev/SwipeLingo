import Foundation
import SwiftData
internal import CoreData

// MARK: - CollectionDedupeObserver
//
// Слушает NSPersistentStoreRemoteChange и перезапускает
// CollectionDedupeService.mergeProtectedCollections на каждое изменение,
// доставленное CloudKit — вместо попытки угадать один момент "синк точно
// закончился" (см. AppSyncStateService.observeCloudKitChanges — тот же
// принцип и то же debounce-значение, уже проверенные в проекте на AppSyncState).
//
// Хранит `ModelContainer`, не `ModelContext` — в отличие от
// AppSyncStateManager/AppSyncStateService (единственные два места в проекте,
// которые сознательно хранят ModelContext как поле MainActor-класса, см.
// предупреждение в AppSyncStateManager.swift), этот класс достаёт актуальный
// `mainContext` из контейнера в момент вызова, а не через сохранённую ссылку —
// описанная там ловушка synthesized deinit к нему не относится.
//
// Создаётся один раз в composition root (SwipeLingoApp.init()) и живёт весь
// процесс — как AppSyncStateService, поэтому наблюдатель NotificationCenter
// никогда не снимается (тот же выбор, что уже сделан там).

@MainActor
final class CollectionDedupeObserver {

    private let container: ModelContainer
    private let dedupeService = CollectionDedupeService()
    private var reloadTask: Task<Void, Never>?

    init(container: ModelContainer) {
        self.container = container
        observeCloudKitChanges()
    }

    /// Немедленный прогон без ожидания уведомления — используется для
    /// подстраховочного вызова при появлении главного экрана (см. AppView),
    /// на случай если соответствующее CloudKit-уведомление пришло раньше, чем
    /// этот наблюдатель успел зарегистрироваться.
    func runNow() {
        dedupeService.mergeProtectedCollections(context: container.mainContext)
    }

    private func observeCloudKitChanges() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main гарантирует главный поток — явно подтверждаем изоляцию MainActor
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            self?.runNow()
        }
    }
}
