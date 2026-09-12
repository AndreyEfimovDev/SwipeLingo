import CoreData
import Foundation
import SwiftData

// MARK: - AppSyncStateManager
// Обрабатывает CRUD в SwiftData и слияние дубликатов для singleton'а AppSyncState.
// CloudKit может создавать дубликаты, если два устройства вставляют запись до завершения синка.

final class AppSyncStateManager {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func getOrCreateAppState() -> AppSyncState {
        let descriptor = FetchDescriptor<AppSyncState>(
            predicate: #Predicate { $0.id == "app_state_singleton" }
        )
        do {
            let results = try modelContext.fetch(descriptor)

            if results.count > 1 {
                log("Detected \(results.count) AppSyncState duplicates — merging", level: .warning)
                return mergeDuplicates(results)
            }

            if let existing = results.first {
                return existing
            }

            // Записи ещё нет — переносим дефолты из UserDefaults (существующие значения @AppStorage)
            let migrated = AppSyncState(
                srsEnabled:            UserDefaults.standard.object(forKey: "srsEnabled") as? Bool ?? true,
                studyStartHour:        {
                    let h = UserDefaults.standard.integer(forKey: "studyStartHour")
                    return h == 0 ? 6 : h
                }(),
                hasCompletedOnboarding: UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"),
                nativeLanguageRaw:     UserDefaults.standard.string(forKey: "nativeLanguage") ?? NativeLanguage.russian.rawValue
            )
            modelContext.insert(migrated)
            saveContext()
            log("AppSyncState created (migrated from UserDefaults)", level: .info)
            return migrated

        } catch {
            log("getOrCreateAppState fetch failed: \(error)", level: .error)
            let fallback = AppSyncState()
            modelContext.insert(fallback)
            return fallback
        }
    }

    func cleanupDuplicates() {
        let descriptor = FetchDescriptor<AppSyncState>(
            predicate: #Predicate { $0.id == "app_state_singleton" }
        )
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
            UserDefaults.standard.set(srsEnabled, forKey: "srsEnabled")
            touch()
        }
    }

    var studyStartHour: Int {
        didSet {
            guard !isReloading else { return }
            appState.studyStartHour = studyStartHour
            UserDefaults.standard.set(studyStartHour, forKey: "studyStartHour")
            touch()
        }
    }

    var hasCompletedOnboarding: Bool {
        didSet {
            guard !isReloading else { return }
            appState.hasCompletedOnboarding = hasCompletedOnboarding
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
            touch()
        }
    }

    var nativeLanguageRaw: String {
        didSet {
            guard !isReloading else { return }
            appState.nativeLanguageRaw = nativeLanguageRaw
            UserDefaults.standard.set(nativeLanguageRaw, forKey: "nativeLanguage")
            touch()
        }
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

        appState = state
        isReloading = true
        srsEnabled = state.srsEnabled
        studyStartHour = state.studyStartHour
        hasCompletedOnboarding = state.hasCompletedOnboarding
        nativeLanguageRaw = state.nativeLanguageRaw
        isReloading = false

        UserDefaults.standard.set(state.srsEnabled, forKey: "srsEnabled")
        UserDefaults.standard.set(state.studyStartHour, forKey: "studyStartHour")
        UserDefaults.standard.set(state.hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(state.nativeLanguageRaw, forKey: "nativeLanguage")

        log("Reloaded from CloudKit — hasOnboarding:\(state.hasCompletedOnboarding) srs:\(state.srsEnabled)", level: .info)
    }

    // MARK: - Private

    private func touch() {
        appState.settingsUpdatedAt = Date()
        manager.saveContext()
    }
}
