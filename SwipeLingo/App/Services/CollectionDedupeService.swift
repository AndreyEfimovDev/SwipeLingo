import Foundation
import SwiftData

// MARK: - CollectionDedupeService
//
// Привязка и слияние дублей системных (protected) коллекций — Inbox/My Sets.
// Та же гонка CloudKit-синхронизации, что решена для AppSyncState (см.
// AppSyncStateManager.claim(firebaseUID:)) и UserProfile (см.
// UserProfileDedupeService): SystemSeeder создаёт эти коллекции синхронно при
// старте, не дожидаясь асинхронного CloudKit-импорта, и на чистой установке
// может создать новую копию поверх той, что чуть позже довезёт CloudKit.
//
// В отличие от AppSyncState (singleton с id, привязанным к аккаунту) и
// UserProfile (естественный ключ firebaseUID уже на модели), у Collection
// раньше не было понятия владельца вообще — только `.name`. `ownerFirebaseUID`
// (см. Collection.swift) вводит тот же bootstrap → account-scoped переход:
// пусто = ещё не привязана, непустое значение = принадлежит конкретному
// Firebase-аккаунту. Это защищает multi-account изоляцию: на общем iCloud, но
// с разными Firebase-аккаунтами на разных устройствах, дубли одного аккаунта
// не должны мержиться с легитимно отдельной парой Inbox/My Sets другого.
//
// Stateless-структура: ModelContext передаётся параметром на каждый вызов, не
// хранится полем — по аналогии с UserProfileDedupeService/PileManagementService,
// не с AppSyncStateManager/AppSyncStateService (единственное исключение в
// проекте, см. предупреждение в AppSyncStateManager.swift).

struct CollectionDedupeService {

    /// Имена защищённых коллекций, подлежащих claim/dedupe-логике. Курируемый
    /// контент сюда не входит — тот уже дедуплицируется по `firestoreId`.
    static let protectedNames: Set<String> = ["Inbox", "My Sets"]

    /// Привязывает bootstrap-копии защищённых коллекций (`ownerFirebaseUID`
    /// пуст) к конкретному Firebase-аккаунту — вызывается один раз после
    /// verified-сессии (см. SwipeLingoApp, `.onChange(of: authService.isSessionVerified)`,
    /// рядом с `appSyncStateService.claim(firebaseUID:)`). До этого вызова
    /// коллекции, созданные `SystemSeeder`, считаются device-wide
    /// bootstrap-записями.
    ///
    /// Для каждого защищённого имени независимо:
    /// 1. Среди коллекций с этим именем уже есть "своя" (ownerFirebaseUID ==
    ///    firebaseUID) — ничего не делаем. Слияние дублей внутри "своих" —
    ///    отдельная забота, см. `mergeProtectedCollections`.
    /// 2. Иначе — все непривязанные (bootstrap) копии с этим именем
    ///    присваиваются этому аккаунту (может быть больше одной, если
    ///    гонка успела создать дубль до claim — mergeProtectedCollections
    ///    схлопнет их позже).
    /// 3. Иначе (есть только чужие, с другим ownerFirebaseUID) — не трогаем;
    ///    свою копию для этого аккаунта на следующем запуске создаст
    ///    account-aware `SystemSeeder`.
    func claimSystemCollections(firebaseUID: String, context: ModelContext) {
        guard !firebaseUID.isEmpty else { return }
        guard let all = try? context.fetch(FetchDescriptor<Collection>()) else { return }

        for name in Self.protectedNames {
            let matches = all.filter { $0.name == name && $0.isUserCreated }
            let alreadyOwn = matches.contains { $0.ownerFirebaseUID == firebaseUID }
            guard !alreadyOwn else { continue }

            let bootstrap = matches.filter { $0.ownerFirebaseUID.isEmpty }
            guard !bootstrap.isEmpty else { continue }

            for collection in bootstrap {
                collection.ownerFirebaseUID = firebaseUID
            }
            log("Collection '\(name)' claimed (bootstrap → account)", level: .info)
        }

        context.saveWithErrorHandling()
    }

    /// Мержит дубли защищённых коллекций — по одной "выжившей" копии на пару
    /// (имя, `ownerFirebaseUID`). Коллекции с РАЗНЫМ `ownerFirebaseUID`
    /// (в том числе пустой bootstrap vs привязанный к аккаунту) никогда не
    /// мержатся между собой — см. заголовочный комментарий про multi-account
    /// изоляцию. Безопасно вызывать многократно (идемпотентно) — при
    /// отсутствии дублей ничего не делает.
    ///
    /// Победитель — самый старый по `createdAt` (тот же принцип, что в
    /// `AppSyncStateManager.mergeDuplicates`/`UserProfileDedupeService.resolveProfile`).
    /// В отличие от тех двух — здесь дубли держат реальный контент, поэтому
    /// перед удалением выполняется reparenting: `CardSet.collectionId` дублей
    /// переносится на выжившую коллекцию, а затем одноимённые `CardSet`
    /// внутри неё (например, два "Inbox" после переноса) сливаются в один
    /// через `mergeDuplicateCardSets`. Сами карточки на дубликаты `en` внутри
    /// слитого сета не проверяются — это отдельное мягкое UI-правило
    /// (`AddEditCardView`), не инвариант хранилища, и вне рамок этой функции.
    func mergeProtectedCollections(context: ModelContext) {
        guard let allCollections = try? context.fetch(FetchDescriptor<Collection>()) else { return }

        var didMergeAnything = false

        for name in Self.protectedNames {
            let matches = allCollections.filter { $0.name == name && $0.isUserCreated }
            let groupedByOwner = Dictionary(grouping: matches, by: { $0.ownerFirebaseUID })

            for (_, group) in groupedByOwner where group.count > 1 {
                mergeCollectionGroup(group, context: context)
                didMergeAnything = true
            }
        }

        guard didMergeAnything else { return }
        context.saveWithErrorHandling()
    }

    // MARK: - Private

    private func mergeCollectionGroup(_ group: [Collection], context: ModelContext) {
        let sorted = group.sorted { $0.createdAt < $1.createdAt }
        guard let primary = sorted.first else { return }
        let duplicates = Array(sorted.dropFirst())

        let allSets = (try? context.fetch(FetchDescriptor<CardSet>())) ?? []
        for duplicate in duplicates {
            for set in allSets where set.collectionId == duplicate.id {
                set.collectionId = primary.id
            }
        }

        mergeDuplicateCardSets(collectionId: primary.id, context: context)

        for duplicate in duplicates {
            context.delete(duplicate)
        }
        log("Merged \(group.count) '\(primary.name)' duplicates → 1 Collection", level: .info)
    }

    private func mergeDuplicateCardSets(collectionId: UUID, context: ModelContext) {
        guard let allSets = try? context.fetch(FetchDescriptor<CardSet>()) else { return }
        let setsInCollection = allSets.filter { $0.collectionId == collectionId }
        let groupedByName = Dictionary(grouping: setsInCollection, by: { $0.name })

        for (_, sets) in groupedByName where sets.count > 1 {
            let sortedSets = sets.sorted { $0.createdAt < $1.createdAt }
            guard let primarySet = sortedSets.first else { continue }
            let duplicateSets = Array(sortedSets.dropFirst())

            let allCards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
            for duplicateSet in duplicateSets {
                for card in allCards where card.setId == duplicateSet.id {
                    card.setId = primarySet.id
                }
                context.delete(duplicateSet)
            }
            log("Merged \(sets.count) '\(primarySet.name)' duplicate CardSets → 1", level: .info)
        }
    }
}
