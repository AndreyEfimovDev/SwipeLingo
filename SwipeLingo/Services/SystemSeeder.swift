import Foundation
import SwiftData

// MARK: - SystemSeeder
//
// Ensures system collections (My Sets, Inbox) always exist on every launch.
// Curated content (Collections → CardSets → Cards) comes from Firestore via FirestoreImportService.

struct SystemSeeder {

    /// Creates "My Sets" and "Inbox" if they are missing.
    /// Safe to call on every launch — only inserts what is absent.
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
