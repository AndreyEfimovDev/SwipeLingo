internal import CoreData
import Foundation
import SwiftData

// MARK: - AppSyncStateService
// @Observable-сервис, раздающий синхронизированные настройки по всему приложению.
// Пишет и в SwiftData (CloudKit-синк), и в UserDefaults (немедленная совместимость с @AppStorage).
// Слушает NSPersistentStoreRemoteChange, чтобы реагировать на обновления, доставленные CloudKit.

@Observable
@MainActor
final class AppSyncStateService {

    private let modelContext: ModelContext
    private let manager: AppSyncStateManager
    private var appState: AppSyncState

    // MARK: - Синхронизируемые свойства
    // Каждый setter пишет и в UserDefaults (совместимость с @AppStorage), и в SwiftData (CloudKit).

    // isReloading подавляет сохранения в didSet во время перезагрузки, инициированной CloudKit
    private var isReloading = false

    var srsEnabled: Bool {
        didSet {
            guard !isReloading else { return }
            appState.srsEnabled = srsEnabled
            UserDefaults.standard.set(srsEnabled, forKey: Constants.StorageKey.srsEnabled)
            touch()
        }
    }

    var studyStartHour: Int {
        didSet {
            guard !isReloading else { return }
            appState.studyStartHour = studyStartHour
            UserDefaults.standard.set(studyStartHour, forKey: Constants.StorageKey.studyStartHour)
            touch()
        }
    }

    var hasCompletedOnboarding: Bool {
        didSet {
            guard !isReloading else { return }
            appState.hasCompletedOnboarding = hasCompletedOnboarding
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Constants.StorageKey.hasCompletedOnboarding)
            touch()
        }
    }

    var nativeLanguageRaw: String {
        didSet {
            guard !isReloading else { return }
            appState.nativeLanguageRaw = nativeLanguageRaw
            UserDefaults.standard.set(nativeLanguageRaw, forKey: Constants.StorageKey.nativeLanguage)
            touch()
        }
    }

    /// Типизированная обёртка над `nativeLanguageRaw` — избавляет вызывающий код от
    /// ручного `NativeLanguage(rawValue:) ?? .russian` на каждом чтении/записи.
    var nativeLanguage: NativeLanguage {
        get { NativeLanguage(rawValue: nativeLanguageRaw) ?? .russian }
        set { nativeLanguageRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(modelContext: ModelContext) {
        let mgr = AppSyncStateManager(modelContext: modelContext)
        let state = mgr.getOrCreateAppState()
        self.modelContext = modelContext
        self.manager = mgr
        self.appState = state
        self.srsEnabled = state.srsEnabled
        self.studyStartHour = state.studyStartHour
        self.hasCompletedOnboarding = state.hasCompletedOnboarding
        self.nativeLanguageRaw = state.nativeLanguageRaw

        observeCloudKitChanges()
    }

    // Превентивная мера против бага Swift Concurrency рантайма — см. ⚠️ в
    // заголовочном комментарии AppSyncStateManager выше (тот же паттерн: этот
    // класс тоже хранит ModelContext как поле).
    deinit {}

    // MARK: - Привязка к аккаунту

    /// Привязывает singleton к текущему Firebase-аккаунту — вызывать один раз после
    /// verified-сессии, когда известен `firebaseUID` (см. `SwipeLingoApp`,
    /// `.onChange(of: authService.isSessionVerified)` — срабатывает и на холодный старт
    /// с закэшированной сессией, и на свежий вход, так что вызов из одной точки
    /// покрывает оба случая). До этого вызова сервис работает с device-wide
    /// bootstrap-записью, созданной в `init`.
    /// См. `AppSyncStateManager.claim(firebaseUID:)` — там три исхода (существующая
    /// запись аккаунта / присвоение bootstrap-записи / чистая новая запись).
    func claim(firebaseUID: String) {
        let state = manager.claim(firebaseUID: firebaseUID)
        guard state !== appState else { return }   // уже привязаны к этой же записи — no-op
        apply(state)
    }

    /// См. `AppSyncStateManager.hasForeignAccountData(excluding:)`.
    func hasForeignAccountData(firebaseUID: String) -> Bool {
        manager.hasForeignAccountData(excluding: firebaseUID)
    }

    // MARK: - Наблюдатель CloudKit

    // NSPersistentStoreRemoteChange срабатывает И на локальные сохранения, И на удалённые изменения CloudKit.
    // Без debounce один sync-пакет (CloudKit доставляет много записей) вызвал бы
    // десятки перезагрузок, каждая из которых сохраняет (cleanupDuplicates) → порождая ещё уведомления.
    // Debounce схлопывает пакет в одну перезагрузку через 300мс после последнего уведомления.
    private var reloadTask: Task<Void, Never>?

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
            self?.reloadFromSwiftData()
        }
    }

    private func reloadFromSwiftData() {
        manager.cleanupDuplicates()
        let state = manager.getOrCreateAppState()

        // NSPersistentStoreRemoteChange срабатывает на каждый тип модели (Card, CardSet и т.д.).
        // Пропускаем перезагрузку, если значения AppSyncState реально не изменились — избегаем лишних UI-обновлений.
        let changed = state.srsEnabled            != srsEnabled
                   || state.studyStartHour        != studyStartHour
                   || state.hasCompletedOnboarding != hasCompletedOnboarding
                   || state.nativeLanguageRaw      != nativeLanguageRaw
                   || state.settingsUpdatedAt      != appState.settingsUpdatedAt

        guard changed else {
            log("CloudKit ping — AppSyncState unchanged, skipping reload", level: .info)
            return
        }

        apply(state)
        log("Reloaded from CloudKit — hasOnboarding:\(state.hasCompletedOnboarding) srs:\(state.srsEnabled)", level: .info)
    }

    // MARK: - Private

    /// Применяет `state` как текущий: обновляет `appState` и синхронизированные
    /// `@Observable`-свойства (подавляя их `didSet`, чтобы не записать их же значения
    /// обратно), плюс зеркалирует в `UserDefaults` для совместимости с `@AppStorage`.
    /// Общий код для `claim(firebaseUID:)` и `reloadFromSwiftData()` — оба переключают
    /// сервис на другую запись `AppSyncState`, просто по разным поводам.
    private func apply(_ state: AppSyncState) {
        appState = state
        isReloading = true
        srsEnabled = state.srsEnabled
        studyStartHour = state.studyStartHour
        hasCompletedOnboarding = state.hasCompletedOnboarding
        nativeLanguageRaw = state.nativeLanguageRaw
        isReloading = false

        UserDefaults.standard.set(state.srsEnabled, forKey: Constants.StorageKey.srsEnabled)
        UserDefaults.standard.set(state.studyStartHour, forKey: Constants.StorageKey.studyStartHour)
        UserDefaults.standard.set(state.hasCompletedOnboarding, forKey: Constants.StorageKey.hasCompletedOnboarding)
        UserDefaults.standard.set(state.nativeLanguageRaw, forKey: Constants.StorageKey.nativeLanguage)
    }

    private func touch() {
        appState.settingsUpdatedAt = Date()
        manager.saveContext()
    }
}
