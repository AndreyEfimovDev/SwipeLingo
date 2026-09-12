import Foundation
import SwiftData

// MARK: - SystemSeeder
//
// Гарантирует, что системные коллекции (My Sets, Inbox) всегда существуют при каждом запуске.
// Кураторский контент (Collections → CardSets → Cards) приходит из Firestore через ImportFSService.

struct SystemSeeder {

    /// Создаёт "My Sets" и "Inbox", если их нет.
    /// Безопасно вызывать при каждом запуске — вставляет только отсутствующее.
    ///
    /// Fetch — через явный `do/try/catch`, а не `fetchWithErrorHandling`: та при сбое
    /// молча возвращает `[]`, что здесь означало бы "коллекций не существует" и
    /// привело бы к дублированию "Inbox"/"My Sets" при каждом транзиентном сбое чтения.
    /// SwiftData + CloudKit не поддерживает `@Attribute(.unique)`, так что ничего,
    /// кроме этой проверки, от дублей не защищает — при неудачном fetch безопаснее
    /// пропустить сидинг в этом запуске (и показать пользователю алерт через
    /// `ErrorManager`, как и остальные fetch-сбои в проекте), чем создать копию
    /// защищённой коллекции, которую пользователь не сможет удалить сам
    /// (для Inbox/My Sets context-меню скрыто).
    static func ensureSystemCollections(into context: ModelContext) {
        let existing: [Collection]
        do {
            existing = try context.fetch(FetchDescriptor<Collection>())
        } catch {
            ErrorManager.shared.handle(error, message: SwiftDataError.fetchFailed.message)
            return
        }
        let names = Set(existing.map { $0.name })

        if !names.contains("My Sets") {
            let mySets = Collection(name: "My Sets", icon: "folder", isOwned: true, isUserCreated: true)
            context.insert(mySets)
        }

        if !names.contains("Inbox") {
            let inbox = Collection(name: "Inbox", icon: "tray", isOwned: true, isUserCreated: true)
            context.insert(inbox)
            let set = CardSet(name: "Inbox", collectionId: inbox.id)
            context.insert(set)
        } else if let inbox = existing.first(where: { $0.name == "Inbox" }) {
            let sets: [CardSet]
            do {
                sets = try context.fetch(FetchDescriptor<CardSet>())
            } catch {
                ErrorManager.shared.handle(error, message: SwiftDataError.fetchFailed.message)
                return
            }
            if !sets.contains(where: { $0.collectionId == inbox.id }) {
                let set = CardSet(name: "Inbox", collectionId: inbox.id)
                context.insert(set)
            }
        }

        context.saveWithErrorHandling()
    }
}
