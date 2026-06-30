import CoreData
import Foundation
import SwiftData

// MARK: - AppSyncStateManager
// Handles SwiftData CRUD and duplicate merging for the AppSyncState singleton.
// CloudKit can create duplicates when two devices both insert before sync completes.

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
                log("[AppSync] Detected \(results.count) AppSyncState duplicates — merging", level: .warning)
                return mergeDuplicates(results)
            }

            if let existing = results.first {
                return existing
            }

            // No record yet — migrate defaults from UserDefaults (existing @AppStorage values)
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
            log("[AppSync] AppSyncState created (migrated from UserDefaults)", level: .info)
            return migrated

        } catch {
            log("[AppSync] getOrCreateAppState fetch failed: \(error)", level: .error)
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
        // Primary = most recently updated (wins on conflict)
        let sorted = states.sorted { $0.settingsUpdatedAt > $1.settingsUpdatedAt }
        guard let primary = sorted.first else { return AppSyncState() }

        // hasCompletedOnboarding: true wins (once completed, always completed)
        primary.hasCompletedOnboarding = states.contains { $0.hasCompletedOnboarding }

        // srsEnabled / studyStartHour / nativeLanguageRaw: primary already has newest values

        // Delete duplicates
        for duplicate in sorted.dropFirst() {
            modelContext.delete(duplicate)
        }
        saveContext()
        log("[AppSync] Merged \(states.count) duplicates → 1 AppSyncState", level: .info)
        return primary
    }

    func saveContext() {
        do {
            try modelContext.save()
        } catch {
            log("[AppSync] Save failed: \(error)", level: .error)
        }
    }
}

// MARK: - AppSyncStateService
// @Observable service exposing synced settings throughout the app.
// Writes to both SwiftData (CloudKit sync) and UserDefaults (immediate @AppStorage compat).
// Listens for NSPersistentStoreRemoteChange to react to CloudKit-delivered updates.

@Observable
@MainActor
final class AppSyncStateService {

    private let modelContext: ModelContext
    private let manager: AppSyncStateManager
    private var appState: AppSyncState

    // MARK: - Synced properties
    // Each setter writes to both UserDefaults (@AppStorage compat) and SwiftData (CloudKit).

    // isReloading suppresses didSet saves during CloudKit-triggered reload
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

    // MARK: - CloudKit observer

    private func observeCloudKitChanges() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadFromSwiftData()
            }
        }
    }

    private func reloadFromSwiftData() {
        manager.cleanupDuplicates()
        let state = manager.getOrCreateAppState()
        appState = state

        // Suppress didSet saves — we're reloading FROM SwiftData, not writing TO it
        isReloading = true
//        srsEnabled = state.srsEnabled
        srsEnabled = appState.srsEnabled

        studyStartHour = state.studyStartHour
        hasCompletedOnboarding = state.hasCompletedOnboarding
        nativeLanguageRaw = state.nativeLanguageRaw
        isReloading = false

        // Propagate to UserDefaults so @AppStorage consumers (FlashCardsView etc.) update
        UserDefaults.standard.set(state.srsEnabled, forKey: "srsEnabled")
        UserDefaults.standard.set(state.studyStartHour, forKey: "studyStartHour")
        UserDefaults.standard.set(state.hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(state.nativeLanguageRaw, forKey: "nativeLanguage")

        log("[AppSync] Reloaded from CloudKit — hasOnboarding:\(state.hasCompletedOnboarding) srs:\(state.srsEnabled)", level: .info)
    }

    // MARK: - Private

    private func touch() {
        appState.settingsUpdatedAt = Date()
        manager.saveContext()
    }
}
