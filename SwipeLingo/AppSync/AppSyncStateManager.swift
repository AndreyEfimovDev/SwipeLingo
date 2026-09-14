//
//  AppSyncStateManager.swift
//  SwipeLingo
//
//  Created by Andrey Efimov on 14.09.2026.
//

import CoreData
import Foundation
import SwiftData

// MARK: - AppSyncStateManager
// Обрабатывает CRUD в SwiftData и слияние дубликатов для singleton'а AppSyncState.
// CloudKit может создавать дубликаты, если два устройства вставляют запись до завершения синка.
//
// `currentID` — id записи, с которой сейчас работает менеджер: bootstrap-бакет
// (`Constants.appSyncBootstrapID`) до вызова `claim(firebaseUID:)`, затем — запись,
// закреплённая за конкретным аккаунтом (`"app_state_<uid>"`). Все операции
// (`getOrCreateAppState`, `cleanupDuplicates`) работают именно с `currentID`, а не
// с фиксированной строкой — см. заголовочный комментарий `AppSyncState.swift`.
//
// Фильтрация — через fetch всех записей + `.filter` в Swift, не через
// `FetchDescriptor(predicate: #Predicate { ... })`. Изначально это была попытка
// починить воспроизводимый malloc-краш в юнит-тестах — не помогло, реальная
// причина оказалась не в `#Predicate` (см. ниже), но сам fetch-all остался:
// данных всегда единицы (bootstrap + максимум по записи на аккаунт на
// устройстве), так что это не проблема для производительности, а код чуть проще.
//
// ⚠️ ЛОВУШКА (найдено сентябрь 2026, см. AppSyncStateManagerTests):
// этот класс и AppSyncStateService — ЕДИНСТВЕННЫЕ во всём проекте, что хранят
// `ModelContext` как поле (все остальные сервисы — stateless, ModelContext
// передаётся параметром на каждый вызов, см. PileManagementService). Именно
// из-за этого поймали баг Swift Concurrency рантайма: деаллокация
// MainActor-изолированного класса, хранящего `ModelContext`, крашится
// ("pointer being freed was not allocated") через
// `swift_task_deinitOnExecutorMainActorBackDeploy` — воспроизводится, когда
// приложение собрано более новым тулчейном (Xcode 26.5), но выполняется на
// более старой ОС (iOS 18.5 — ниже, чем deployment target тулчейна), т.е.
// "back-deploy" путь синтезированного deinit. На симуляторе той же версии, что
// Xcode (26.5) — не воспроизводится. Явный `deinit {}` ниже — превентивная
// мера (может изменить путь синтеза компилятора), а не подтверждённый фикс.
// В текущем коде НЕ проявляется в реальном приложении: оба типа создаются один
// раз в SwipeLingoApp.init() и живут весь процесс, никогда не освобождаются во
// время сессии — риск актуален только если когда-нибудь появится код,
// пересоздающий AppDependencies/AppSyncStateService на лету (см. Retry-кнопка
// в Backlog Architecture.md), или если другой класс переймёт этот паттерн
// (хранить ModelContext как поле MainActor-класса).

final class AppSyncStateManager {

    private let modelContext: ModelContext
    private(set) var currentID: String

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.currentID = Constants.appSyncBootstrapID
    }

    deinit {}

    func getOrCreateAppState() -> AppSyncState {
        let id = currentID
        do {
            let results = try modelContext.fetch(FetchDescriptor<AppSyncState>()).filter { $0.id == id }

            if results.count > 1 {
                log("Detected \(results.count) AppSyncState duplicates for '\(id)' — merging", level: .warning)
                return mergeDuplicates(results)
            }

            if let existing = results.first {
                return existing
            }

            // Записи ещё нет.
            if id == Constants.appSyncBootstrapID {
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
        let all = (try? modelContext.fetch(FetchDescriptor<AppSyncState>())) ?? []

        // 1) Уже привязана к этому аккаунту?
        let ownResults = all.filter { $0.id == targetID }
        if !ownResults.isEmpty {
            currentID = targetID
            log("AppSyncState claimed (existing record) for account", level: .info)
            return ownResults.count > 1 ? mergeDuplicates(ownResults) : ownResults[0]
        }

        // 2) Есть непривязанная bootstrap-запись — присваиваем её этому аккаунту.
        let bootstrapResults = all.filter { $0.id == Constants.appSyncBootstrapID }
        if !bootstrapResults.isEmpty {
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
        let unclaimedID = Constants.appSyncBootstrapID
        guard let all = try? modelContext.fetch(FetchDescriptor<AppSyncState>()) else { return false }
        return all.contains { $0.id != myID && $0.id != unclaimedID }
    }

    func cleanupDuplicates() {
        let id = currentID
        guard let all = try? modelContext.fetch(FetchDescriptor<AppSyncState>()) else { return }
        let results = all.filter { $0.id == id }
        guard results.count > 1 else { return }
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
