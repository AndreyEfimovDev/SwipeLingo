internal import CoreData
import Foundation
import SwiftData

<<<<<<< HEAD
// MARK: - AppSyncStateManager
// Обрабатывает CRUD в SwiftData и слияние дубликатов для singleton'а AppSyncState.
// CloudKit может создавать дубликаты, если два устройства вставляют запись до завершения синка.
//
// `currentID` — id записи, с которой сейчас работает менеджер: bootstrap-бакет
// (`unclaimedID`) до вызова `claim(firebaseUID:)`, затем — запись, закреплённая за
// конкретным аккаунтом (`"app_state_<uid>"`). Все операции (`getOrCreateAppState`,
// `cleanupDuplicates`) работают именно с `currentID`, а не с фиксированной строкой —
// см. заголовочный комментарий `AppSyncState.swift`.

final class AppSyncStateManager {

    static let unclaimedID = "app_state_singleton"

    private let modelContext: ModelContext
    private(set) var currentID: String

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.currentID = Self.unclaimedID
    }

    func getOrCreateAppState() -> AppSyncState {
        let id = currentID
        let descriptor = FetchDescriptor<AppSyncState>(predicate: #Predicate { $0.id == id })
        do {
            let results = try modelContext.fetch(descriptor)

            if results.count > 1 {
                log("Detected \(results.count) AppSyncState duplicates for '\(id)' — merging", level: .warning)
                return mergeDuplicates(results)
            }

            if let existing = results.first {
                return existing
            }

            // Записи ещё нет.
            if id == Self.unclaimedID {
                // Bootstrap-бакет — переносим дефолты из UserDefaults (существующие значения @AppStorage).
                let migrated = AppSyncState(
                    srsEnabled: UserDefaults.standard.object(forKey: Constants.StorageKey.srsEnabled) as? Bool ?? true,
                    studyStartHour: {
                        let h = UserDefaults.standard.integer(forKey: Constants.StorageKey.studyStartHour)
                        return h == 0 ? 6 : h
                    }(),
                    hasCompletedOnboarding: UserDefaults.standard.bool(forKey: Constants.StorageKey.hasCompletedOnboarding),
                    nativeLanguageRaw:     UserDefaults.standard.string(forKey: Constants.StorageKey.nativeLanguage) ?? NativeLanguage.russian.rawValue
                )
                modelContext.insert(migrated)
                saveContext()
                log("AppSyncState created (migrated from UserDefaults)", level: .info)
                return migrated
            } else {
                // Запись закреплена за аккаунтом, но её ещё нет — новый аккаунт, чистые дефолты
                // (специально не переносим UserDefaults: те значения могли принадлежать
                // предыдущему аккаунту на этом устройстве).
                let fresh = AppSyncState()
                fresh.id = id
                modelContext.insert(fresh)
                saveContext()
                log("AppSyncState created for account", level: .info)
                return fresh
            }

        } catch {
            log("getOrCreateAppState fetch failed: \(error)", level: .error)
            let fallback = AppSyncState()
            fallback.id = id
            modelContext.insert(fallback)
            return fallback
        }
    }

    /// Привязывает singleton к конкретному Firebase-аккаунту — вызывается один раз
    /// после verified-сессии, когда известен `firebaseUID` (см. `SwipeLingoApp`,
    /// `.onChange(of: authService.isSessionVerified)`). До этого вызова менеджер
    /// работает с device-wide bootstrap-записью (см. `init`).
    ///
    /// Три исхода:
    /// 1. Запись для этого `firebaseUID` уже есть (тот же аккаунт, другое устройство,
    ///    либо повторный вход) — используется она, дубли (если есть) мержатся.
    /// 2. Записи для аккаунта нет, но есть непривязанная bootstrap-запись — она
    ///    присваивается этому аккаунту (её `id` переименовывается), настройки не сбрасываются.
    /// 3. Ни своей записи, ни bootstrap-записи нет (bootstrap уже занят другим
    ///    аккаунтом на этом же iCloud) — создаётся отдельная запись для этого аккаунта
    ///    с чистыми дефолтами. Чужая запись при этом не читается и не изменяется.
    @discardableResult
    func claim(firebaseUID: String) -> AppSyncState {
        let targetID = "app_state_\(firebaseUID)"

        // 1) Уже привязана к этому аккаунту?
        let ownDescriptor = FetchDescriptor<AppSyncState>(predicate: #Predicate { $0.id == targetID })
        if let ownResults = try? modelContext.fetch(ownDescriptor), !ownResults.isEmpty {
            currentID = targetID
            log("AppSyncState claimed (existing record) for account", level: .info)
            return ownResults.count > 1 ? mergeDuplicates(ownResults) : ownResults[0]
        }

        // 2) Есть непривязанная bootstrap-запись — присваиваем её этому аккаунту.
        let unclaimedID = Self.unclaimedID
        let bootstrapDescriptor = FetchDescriptor<AppSyncState>(predicate: #Predicate { $0.id == unclaimedID })
        if let bootstrapResults = try? modelContext.fetch(bootstrapDescriptor), !bootstrapResults.isEmpty {
            let resolved = bootstrapResults.count > 1 ? mergeDuplicates(bootstrapResults) : bootstrapResults[0]
            resolved.id = targetID
            saveContext()
            currentID = targetID
            log("AppSyncState claimed (bootstrap → account) for account", level: .info)
            return resolved
        }

        // 3) Ни своей, ни bootstrap-записи — новая, изолированная от чужих данных.
        currentID = targetID
        return getOrCreateAppState()
    }

    /// Есть ли в локальном хранилище запись `AppSyncState`, принадлежащая ДРУГОМУ
    /// аккаунту (не `firebaseUID` и не непривязанный bootstrap-бакет)? Общий iCloud,
    /// но другой реальный Firebase-аккаунт на этом устройстве — см. заголовочный
    /// комментарий `AppSyncState.swift`. Используется для предупреждения
    /// пользователя — см. `ForeignAccountWarningService`.
    func hasForeignAccountData(excluding firebaseUID: String) -> Bool {
        let myID = "app_state_\(firebaseUID)"
        let unclaimedID = Self.unclaimedID
        guard let all = try? modelContext.fetch(FetchDescriptor<AppSyncState>()) else { return false }
        return all.contains { $0.id != myID && $0.id != unclaimedID }
    }

    func cleanupDuplicates() {
        let id = currentID
        let descriptor = FetchDescriptor<AppSyncState>(predicate: #Predicate { $0.id == id })
        guard let results = try? modelContext.fetch(descriptor), results.count > 1 else { return }
        _ = mergeDuplicates(results)
    }

    // MARK: - Private

    private func mergeDuplicates(_ states: [AppSyncState]) -> AppSyncState {
        // Primary = самая недавно обновлённая (побеждает при конфликте)
        let sorted = states.sorted { $0.settingsUpdatedAt > $1.settingsUpdatedAt }
        guard let primary = sorted.first else { return AppSyncState() }

        // hasCompletedOnboarding: true побеждает (раз завершено — значит завершено навсегда)
        primary.hasCompletedOnboarding = states.contains { $0.hasCompletedOnboarding }

        // srsEnabled / studyStartHour / nativeLanguageRaw: у primary уже самые свежие значения

        // Удаляем дубликаты
        for duplicate in sorted.dropFirst() {
            modelContext.delete(duplicate)
        }
        saveContext()
        log("Merged \(states.count) duplicates → 1 AppSyncState", level: .info)
        return primary
    }

    func saveContext() {
        do {
            try modelContext.save()
        } catch {
            log("Save failed: \(error)", level: .error)
        }
    }
}

=======
>>>>>>> dev
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

<<<<<<< HEAD
=======
    // Превентивная мера против бага Swift Concurrency рантайма — см. ⚠️ в
    // заголовочном комментарии AppSyncStateManager выше (тот же паттерн: этот
    // класс тоже хранит ModelContext как поле).
    deinit {}

>>>>>>> dev
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
