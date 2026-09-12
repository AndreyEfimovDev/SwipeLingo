import SwiftUI
import SwiftData

// MARK: - PairsLibraryViewModel
//
// Бизнес-логика PairsLibraryView: фильтрация PairsSets/PairsPiles по CEFR-уровню
// пользователя и мягкому удалению, sync с Firestore, мутации Pile (делегируются в
// PileManagementService) и Set (soft-delete/restore). @Query-результаты остаются во
// View и передаются сюда параметром — та же конвенция, что в LibraryViewModel.
// Sheet/alert/disclosure-состояние (showAllPiles, pileSheet, setToDelete и т.п.)
// остаётся во View как @State — навигационная часть экрана.

@Observable
final class PairsLibraryViewModel {

    private(set) var isSyncing = false

    private let pileService = PileManagementService()

    // MARK: - Фильтрация

    func userLevel(profiles: [UserProfile]) -> CEFRLevel {
        profiles.first?.cefrLevel ?? .c2
    }

    /// Видимые (не мягко-удалённые) сеты коллекции, доступные на уровне пользователя.
    func sets(for collection: Collection, allSets: [PairsSet], userLevel: CEFRLevel) -> [PairsSet] {
        allSets.filter { $0.collectionId == collection.id && $0.cefrLevel <= userLevel && !$0.isSoftDeleted }
    }

    func deletedSets(allSets: [PairsSet]) -> [PairsSet] {
        allSets.filter { $0.isSoftDeleted }
    }

    /// Только коллекции с хотя бы одним видимым сетом — пустые скрываем (кратковременно
    /// появляются во время sync, пока cleanup ещё не удалил их).
    func visiblePairsCollections(pairsCollections: [Collection], allSets: [PairsSet], userLevel: CEFRLevel) -> [Collection] {
        pairsCollections.filter { !sets(for: $0, allSets: allSets, userLevel: userLevel).isEmpty }
    }

    /// Сеты без коллекции или с неизвестным collectionId.
    func orphanedSets(allSets: [PairsSet], visibleCollections: [Collection]) -> [PairsSet] {
        let knownIds = Set(visibleCollections.map(\.id))
        return allSets.filter { set in
            guard !set.isSoftDeleted else { return false }
            guard let colId = set.collectionId else { return true }
            return !knownIds.contains(colId)
        }
    }

    /// Сводка для строки пайла: количество сетов и суммарное число пар в них.
    func pileSummary(for pile: PairsPile, allSets: [PairsSet]) -> (setCount: Int, pairCount: Int) {
        let sets = PairsPileService().sets(for: pile, from: allSets)
        return (sets.count, sets.reduce(0) { $0 + $1.items.count })
    }

    // MARK: - Синхронизация

    /// Ручной sync = full sync: запускает orphan removal и гарантирует актуальность данных.
    /// `nativeLangRaw` — сырое значение из `@AppStorage`; если оно не распознано, используем `.russian`.
    func syncContent(context: ModelContext, nativeLangRaw: String, level: CEFRLevel) async {
        isSyncing = true
        defer { isSyncing = false }
        let language = NativeLanguage(rawValue: nativeLangRaw) ?? .russian
        await ImportFSService().syncFromFirestore(into: context, language: language, upToLevel: level, forceFullSync: true)
    }

    // MARK: - Pile-мутации (делегируются в PileManagementService)

    func activatePile(_ pile: PairsPile, among allPiles: [PairsPile], context: ModelContext) {
        pileService.activate(pile, among: allPiles, context: context)
    }

    func deletePile(_ pile: PairsPile, context: ModelContext) {
        pileService.delete(pile, context: context)
    }

    func toggleSet(_ set: PairsSet, in pile: PairsPile, context: ModelContext) {
        pileService.toggleSet(set.id, in: pile, context: context)
    }

    /// Создаёт новый Pile с одним сетом `set`.
    /// - Returns: `true`, если пайл был создан (имя не оказалось пустым) — вызывающая
    ///   сторона использует это, чтобы раскрыть список пайлов и показать новый.
    @discardableResult
    func createNewPile(named name: String, with set: PairsSet, context: ModelContext) -> Bool {
        pileService.createPairsPile(named: name, setId: set.id, context: context)
    }

    // MARK: - Set-мутации

    /// Мягко удаляет сет — скрывается из библиотеки, восстановим из "Deleted Sets".
    func deleteSet(_ set: PairsSet, context: ModelContext) {
        set.isSoftDeleted = true
        context.saveWithErrorHandling()
    }

    func restoreSet(_ set: PairsSet, context: ModelContext) {
        set.isSoftDeleted = false
        context.saveWithErrorHandling()
    }
}
