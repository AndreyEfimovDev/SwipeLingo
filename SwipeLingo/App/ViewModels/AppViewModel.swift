import SwiftUI
import SwiftData

// MARK: - AppViewModel

@Observable
final class AppViewModel {

    var studyMode: StudyMode {
        didSet {
            UserDefaults.standard.set(studyMode.label, forKey: Constants.StorageKey.studyMode)
        }
    }
    var activeSheet: AppSheet? = nil

    init() {
        let saved = UserDefaults.standard.string(forKey: Constants.StorageKey.studyMode) ?? ""
        studyMode = StudyMode.allCases.first { $0.label == saved } ?? .cards
    }

    /// Реакция на изменение CEFR-уровня пользователя (вызывается из `AppView.onChange`
    /// по `profiles.first?.cefrLevelRaw`).
    ///
    /// При ПОНИЖЕНИИ уровня — no-op: контент нужного уровня уже скачан локально,
    /// UI отфильтрует мгновенно, повторная синхронизация не нужна.
    /// При ПОВЫШЕНИИ — форсированный full sync: обычный delta-запрос
    /// (`updatedAt > lastSyncedAt`) не подойдёт, потому что сеты нового уровня могут
    /// иметь `updatedAt` старше `lastSyncedAt` и не попасть в выборку.
    ///
    /// `context`/`nativeLanguage` передаются параметрами, а не читаются из
    /// `Environment`/сервиса внутри — `@Query`/`modelContext` по правилам MVVM
    /// остаются во View, а `nativeLanguage` берётся из единственного источника
    /// правды (`AppSyncStateService`), которым владеет View через `dependencies`.
    func handleCEFRLevelChange(
        oldRaw: String?,
        newRaw: String?,
        nativeLanguage: NativeLanguage,
        context: ModelContext
    ) {
        guard let newLevel = Self.levelIncrease(oldRaw: oldRaw, newRaw: newRaw) else { return }   // понижение — sync не нужен
        Task {
            await ImportFSService().syncFromFirestore(
                into: context,
                language: nativeLanguage,
                upToLevel: newLevel,
                forceFullSync: true
            )
        }
    }

    /// Чистая логика сравнения уровней, вынесена из `handleCEFRLevelChange` отдельно
    /// от side-effect (сетевой sync) — тестируется без моков и сети. `ImportFSService`
    /// не имеет протокола-обёртки (в отличие от `AuthClient`/`FirestoreClient`), так
    /// что сам факт вызова sync юнит-тестом не проверить — эта функция покрывает
    /// именно решение "нужен ли sync", а не сам sync.
    /// - Returns: новый уровень, если это повышение (используется как `upToLevel` для
    ///   sync), либо `nil` при понижении/равенстве — вызывающая сторона ничего не делает.
    static func levelIncrease(oldRaw: String?, newRaw: String?) -> CEFRLevel? {
        let oldLevel = CEFRLevel(rawValue: oldRaw ?? "") ?? .c2
        let newLevel = CEFRLevel(rawValue: newRaw ?? "") ?? .c2
        return newLevel > oldLevel ? newLevel : nil
    }

    // MARK: - StudyMode

    enum StudyMode: String, CaseIterable {
        case cards
        case pairs
        case books

        var icon: String {
            switch self {
            case .cards: return "rectangle.stack"
            case .pairs: return "sparkles"
            case .books: return "book.closed"
            }
        }

        var label: String {
            switch self {
            case .cards: return "Cards"
            case .pairs: return "Pairs"
            case .books: return "Books"
            }
        }

        var other: StudyMode {
            switch self {
            case .cards: return .pairs
            case .pairs: return .books
            case .books: return .cards
            }
        }
    }

    // MARK: - AppSheet

    enum AppSheet: String, Identifiable {
        case cardsLibrary
        case pairsLibrary
        case statistics
        case settings

        var id: String { rawValue }
    }
}

// MARK: - Theme

enum Theme: String, CaseIterable {
    case light
    case dark
    case system

    var displayName: String {
        switch self {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .system: return "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}

