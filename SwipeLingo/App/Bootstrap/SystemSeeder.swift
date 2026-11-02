import Foundation
import SwiftData

// MARK: - SystemSeeder
//
// Гарантирует, что системная коллекция Inbox и защищённый сет Inbox внутри неё
// всегда существуют при каждом запуске. Кураторский контент (Collections → CardSets →
// Cards) приходит из Firestore через ImportFSService.
//
// Inbox — не отдельная Collection (было так до рефакторинга сентября 2026), а обычный
// CardSet внутри системной коллекции, защищённый от удаления по имени (см. `cardSet.name == "Inbox"`
// в CardSetDetailView/CardsLibraryView/DeletedCardsViewModel) — раз Inbox physически
// всегда содержит ровно один сет, отдельная Collection только ради этого единственного
// сета не нужна: одна защищённая системная коллекция вместо двух, соответственно вдвое
// меньше edge-cases в CollectionDedupeService (claim/merge только для системной коллекции).

struct SystemSeeder {

    /// Создаёт системную коллекцию Inbox (если её нет) и гарантирует, что внутри неё есть Inbox CardSet.
    /// Безопасно вызывать при каждом запуске — вставляет только отсутствующее.
    ///
    /// Fetch — через явный `do/try/catch`, а не `fetchWithErrorHandling`: та при сбое
    /// молча возвращает `[]`, что здесь означало бы "коллекции не существует" и
    /// привело бы к дублированию системной коллекции при каждом транзиентном сбое чтения.
    /// SwiftData + CloudKit не поддерживает `@Attribute(.unique)`, так что ничего,
    /// кроме этой проверки, от дублей не защищает — при неудачном fetch безопаснее
    /// пропустить сидинг в этом запуске (и показать пользователю алерт через
    /// `ErrorManager`, как и остальные fetch-сбои в проекте), чем создать копию
    /// защищённой коллекции, которую пользователь не сможет удалить сам
    /// (для неё context-меню скрыто).
    static func ensureSystemCollections(into context: ModelContext) {
        let existing: [Collection]
        do {
            existing = try context.fetch(FetchDescriptor<Collection>())
        } catch {
            ErrorManager.shared.handle(error, message: SwiftDataError.fetchFailed.message)
            return
        }

        let inboxCollection: Collection
        if let found = existing.first(where: { $0.isInbox }) {
            inboxCollection = found
        } else {
            inboxCollection = Collection(name: Collection.inboxCollectionName, icon: "folder", isOwned: true, isUserCreated: true)
            context.insert(inboxCollection)
        }

        let sets: [CardSet]
        do {
            sets = try context.fetch(FetchDescriptor<CardSet>())
        } catch {
            ErrorManager.shared.handle(error, message: SwiftDataError.fetchFailed.message)
            return
        }
        if !sets.contains(where: { $0.name == "Inbox" && $0.collectionId == inboxCollection.id }) {
            let inboxSet = CardSet(name: "Inbox", collectionId: inboxCollection.id)
            context.insert(inboxSet)
        }

        context.saveWithErrorHandling()
    }
}
