import Foundation
import SwiftData

// MARK: - SystemSeeder
//
// Гарантирует, что системные коллекции (My Sets, Inbox) всегда существуют при каждом запуске.
// Кураторский контент (Collections → CardSets → Cards) приходит из Firestore через ImportFSService.

struct SystemSeeder {

    /// Создаёт "My Sets" и "Inbox", если их нет.
    /// Безопасно вызывать при каждом запуске — вставляет только отсутствующее.
    static func ensureSystemCollections(into context: ModelContext) {
        let existing = context.fetchWithErrorHandling(FetchDescriptor<Collection>())
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
            let sets = context.fetchWithErrorHandling(FetchDescriptor<CardSet>())
            if !sets.contains(where: { $0.collectionId == inbox.id }) {
                let set = CardSet(name: "Inbox", collectionId: inbox.id)
                context.insert(set)
            }
        }

        context.saveWithErrorHandling()
    }
}
