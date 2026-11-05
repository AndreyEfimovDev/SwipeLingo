import Foundation
import SwiftData

// MARK: - CloudContentDedupeService
//
// Схлопывает дубли облачного контента (Collection/CardSet/Card/PairsSet с одним `firestoreId`). Та же гонка
// CloudKit, что у книг (BookCatalogDedupeService) и системной коллекции (CollectionDedupeService): синк
// ImportFSService не находит контент локально и вставляет свои копии, а чуть позже CloudKit довозит копии
// с прошлой установки или с другого устройства. Сопоставление по `firestoreId` в ImportFSService защищает
// только от повторной вставки внутри одного устройства, не от этой гонки.
//
// Порядок сверху вниз: коллекции → сеты → карточки, чтобы дубли нижнего уровня, переехавшие к выжившему
// родителю, схлопнулись в том же проходе. Выбор выжившей копии детерминирован (полный порядок до `id`) —
// на всех устройствах выживает одна и та же запись, и CloudKit не гоняет удаления туда-обратно.
//
// Облачный контент общий для всех аккаунтов на этом iCloud (владельца у него нет), поэтому, в отличие от
// CollectionDedupeService, фильтрации по владельцу здесь нет.
//
// Stateless-структура: ModelContext передаётся параметром на каждый вызов.

struct CloudContentDedupeService {

    /// Когда искать дубли карточек.
    enum CardCheck {
        /// Всегда — перед синком контента (дубли карточек бывают и без дублей сетов: два синка подряд вставили
        /// одни и те же карточки в существующий сет).
        case always
        /// Только если в этом проходе схлопнулись сеты — для частого вызова на каждое изменение из CloudKit,
        /// чтобы не читать все карточки без нужды.
        case onlyAfterSetMerge
    }

    /// Схлопывает дубли облачного контента с одинаковым `firestoreId`, перенося ссылки и прогресс на выжившие
    /// копии. Сохраняет контекст, только если что-то изменилось.
    /// - Parameters:
    ///   - context: контекст SwiftData.
    ///   - cardCheck: когда искать дубли карточек (см. `CardCheck`).
    /// - Returns: число удалённых дублей (всех типов вместе).
    @discardableResult
    func mergeDuplicates(context: ModelContext, cardCheck: CardCheck = .always) -> Int {
        var removed = mergeCollections(context: context)
        let removedSets = mergeCardSets(context: context)
        removed += removedSets
        if cardCheck == .always || removedSets > 0 {
            removed += mergeCards(context: context)
        }
        removed += mergePairsSets(context: context)

        if removed > 0 {
            context.saveWithErrorHandling()
            log("Removed \(removed) duplicate(s) of cloud content", level: .info)
        }
        return removed
    }

    // MARK: - Collections

    /// Выживает самая старая копия (`createdAt`, затем `id`) — как у системной коллекции; сеты и PairsSet
    /// дублей переводятся на неё.
    private func mergeCollections(context: ModelContext) -> Int {
        let collections = context.fetchWithErrorHandling(
            FetchDescriptor<Collection>(predicate: #Predicate { !$0.isUserCreated })
        )
        let groups = duplicateGroups(collections, key: \.firestoreId)
        guard !groups.isEmpty else { return 0 }

        let cardSets  = context.fetchWithErrorHandling(FetchDescriptor<CardSet>())
        let pairsSets = context.fetchWithErrorHandling(FetchDescriptor<PairsSet>())
        var removed = 0

        for group in groups {
            let sorted = group.sorted { isOlder($0.createdAt, $0.id, than: $1.createdAt, $1.id) }
            guard let survivor = sorted.first else { continue }
            let duplicates = sorted.dropFirst()
            let duplicateIds = Set(duplicates.map(\.id))

            for set in cardSets where duplicateIds.contains(set.collectionId) {
                set.collectionId = survivor.id
            }
            for set in pairsSets {
                if let collectionId = set.collectionId, duplicateIds.contains(collectionId) {
                    set.collectionId = survivor.id
                }
            }
            for duplicate in duplicates { context.delete(duplicate) }
            removed += duplicates.count
        }
        return removed
    }

    // MARK: - CardSets

    /// Выживает самая старая копия (`createdAt`, затем `id`); карточки и пайлы переводятся на неё.
    /// Мягкое удаление любой копии переходит на выжившую — явное действие пользователя важнее.
    private func mergeCardSets(context: ModelContext) -> Int {
        let sets = context.fetchWithErrorHandling(
            FetchDescriptor<CardSet>(predicate: #Predicate { !$0.isUserCreated })
        )
        let groups = duplicateGroups(sets, key: \.firestoreId)
        guard !groups.isEmpty else { return 0 }

        let cards = context.fetchWithErrorHandling(FetchDescriptor<Card>())
        let piles = context.fetchWithErrorHandling(FetchDescriptor<Pile>())
        var replacements: [UUID: UUID] = [:]
        var removed = 0

        for group in groups {
            let sorted = group.sorted { isOlder($0.createdAt, $0.id, than: $1.createdAt, $1.id) }
            guard let survivor = sorted.first else { continue }
            let duplicates = sorted.dropFirst()

            if duplicates.contains(where: \.isSoftDeleted) { survivor.isSoftDeleted = true }
            for duplicate in duplicates {
                replacements[duplicate.id] = survivor.id
                context.delete(duplicate)
            }
            removed += duplicates.count
        }

        for card in cards {
            if let survivorId = replacements[card.setId] { card.setId = survivorId }
        }
        for pile in piles {
            pile.setIds = Self.replacingIds(in: pile.setIds, with: replacements)
        }
        return removed
    }

    // MARK: - Cards

    /// Дубли ищутся внутри сета (`setId` + `firestoreId`). Выживает копия, которую проверяли последней
    /// (`lastReviewed`, затем `id`) — вместе с ней сохраняется SRS-прогресс. Остальное объединяется:
    /// статус — самое сильное решение пользователя (удалена > выучена > активна), избранное — если отмечена
    /// в любой копии, `isNew` — только если новой была каждая, примеры пользователя — у первой копии, где они есть.
    private func mergeCards(context: ModelContext) -> Int {
        // Фильтр в Swift, не #Predicate по опциональной строке (известный SIGILL SwiftData).
        let cards = context.fetchWithErrorHandling(FetchDescriptor<Card>()).filter { $0.firestoreId != nil }
        let groups = Dictionary(grouping: cards) { CardKey(setId: $0.setId, firestoreId: $0.firestoreId ?? "") }
            .values.filter { $0.count > 1 }
        guard !groups.isEmpty else { return 0 }

        var removed = 0
        for group in groups {
            let sorted = group.sorted {
                $0.lastReviewed != $1.lastReviewed
                    ? $0.lastReviewed > $1.lastReviewed
                    : $0.id.uuidString < $1.id.uuidString
            }
            guard let survivor = sorted.first else { continue }
            let duplicates = sorted.dropFirst()

            if let strongest = group.map(\.status).max(by: { Self.statusRank($0) < Self.statusRank($1) }) {
                survivor.status = strongest
            }
            if group.contains(where: \.isFavorite) { survivor.isFavorite = true }
            survivor.isNew = group.allSatisfy(\.isNew)
            if survivor.userSampleEN.isEmpty,
               let donor = duplicates.first(where: { !$0.userSampleEN.isEmpty }) {
                survivor.userSampleEN   = donor.userSampleEN
                survivor.userSampleItem = donor.userSampleItem
            }
            for duplicate in duplicates { context.delete(duplicate) }
            removed += duplicates.count
        }
        return removed
    }

    // MARK: - PairsSets

    /// У PairsSet свой SRS-прогресс, поэтому выживает копия, которую проверяли последней (`lastReviewed`,
    /// затем `createdAt` и `id`); пайлы переводятся на неё. Мягкое удаление и `isNew` — как у сетов/карточек.
    private func mergePairsSets(context: ModelContext) -> Int {
        let sets = context.fetchWithErrorHandling(FetchDescriptor<PairsSet>())
        let groups = duplicateGroups(sets, key: \.firestoreId)
        guard !groups.isEmpty else { return 0 }

        let piles = context.fetchWithErrorHandling(FetchDescriptor<PairsPile>())
        var replacements: [UUID: UUID] = [:]
        var removed = 0

        for group in groups {
            let sorted = group.sorted {
                $0.lastReviewed != $1.lastReviewed
                    ? $0.lastReviewed > $1.lastReviewed
                    : isOlder($0.createdAt, $0.id, than: $1.createdAt, $1.id)
            }
            guard let survivor = sorted.first else { continue }
            let duplicates = sorted.dropFirst()

            if duplicates.contains(where: \.isSoftDeleted) { survivor.isSoftDeleted = true }
            survivor.isNew = group.allSatisfy(\.isNew)
            for duplicate in duplicates {
                replacements[duplicate.id] = survivor.id
                context.delete(duplicate)
            }
            removed += duplicates.count
        }

        for pile in piles {
            pile.setIds = Self.replacingIds(in: pile.setIds, with: replacements)
        }
        return removed
    }

    // MARK: - Helpers

    private struct CardKey: Hashable {
        let setId: UUID
        let firestoreId: String
    }

    /// Группы записей с одинаковым непустым ключом, в которых больше одной записи.
    private func duplicateGroups<T>(_ items: [T], key: (T) -> String?) -> [[T]] {
        let keyed = items.compactMap { item in key(item).map { (key: $0, item: item) } }
        return Dictionary(grouping: keyed, by: { $0.key })
            .values
            .filter { $0.count > 1 }
            .map { group in group.map { $0.item } }
    }

    /// Полный порядок «старше»: по дате, при равенстве — по `id`, чтобы выбор совпадал на всех устройствах
    /// (у копий одного сета `createdAt` берётся из одного документа Firestore и обычно равен).
    private func isOlder(_ lhsDate: Date, _ lhsId: UUID, than rhsDate: Date, _ rhsId: UUID) -> Bool {
        lhsDate != rhsDate ? lhsDate < rhsDate : lhsId.uuidString < rhsId.uuidString
    }

    /// Ранг статуса для объединения: чем сильнее решение пользователя, тем выше.
    private static func statusRank(_ status: CardStatus) -> Int {
        switch status {
        case .active:  0
        case .learnt:  1
        case .deleted: 2
        }
    }

    /// Заменяет id дублей на id выживших, убирая повторы и сохраняя порядок (он задаёт показ при Sequential).
    /// - Parameters:
    ///   - ids: исходные id сетов пайла.
    ///   - replacements: соответствие «id дубля → id выжившего».
    /// - Returns: новый список id; совпадает с исходным, если заменять нечего.
    static func replacingIds(in ids: [UUID], with replacements: [UUID: UUID]) -> [UUID] {
        guard ids.contains(where: { replacements[$0] != nil }) else { return ids }
        var seen = Set<UUID>()
        return ids.compactMap { id in
            let mapped = replacements[id] ?? id
            return seen.insert(mapped).inserted ? mapped : nil
        }
    }
}
