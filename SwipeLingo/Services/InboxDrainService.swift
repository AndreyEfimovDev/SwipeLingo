import Foundation
import SwiftData

// MARK: - InboxDrainService
//
// Читает слова, поставленные в очередь Share Extension через shared App Group
// UserDefaults, и вставляет их как Card в Inbox CardSet. Вынесен из SwipeLingoApp —
// это бизнес-логика (SwiftData-мутации, дедупликация), а не забота точки входа.

struct InboxDrainService {

    /// Разгружает очередь pending-слов (записанную SwipeLingoShare) в Inbox CardSet.
    /// No-op, если очередь пуста. Если Inbox CardSet не резолвится — слова
    /// возвращаются обратно в очередь, а не теряются.
    func drain(container: ModelContainer) {
        let defaults = UserDefaults(suiteName: Constants.appGroupID)
        let pendingKey = Constants.StorageKey.pendingInboxWords
        guard
            let pending = defaults?.stringArray(forKey: pendingKey),
            !pending.isEmpty
        else { return }

        // Clear the queue immediately so a second foreground transition can't
        // re-import the same words if SwiftData save is slow.
        defaults?.removeObject(forKey: pendingKey)

        let context = ModelContext(container)

        // Resolve the Inbox CardSet — it is guaranteed to exist after
        // MockDataSeeder runs, but guard defensively.
        let allSets = context.fetchWithErrorHandling(FetchDescriptor<CardSet>())
        guard let inboxSet = allSets.first(where: { $0.name == "Inbox" }) else {
            log("[InboxDrain] Inbox CardSet not found — re-queuing \(pending.count) word(s)", level: .warning)
            var current = defaults?.stringArray(forKey: pendingKey) ?? []
            current.insert(contentsOf: pending, at: 0)
            defaults?.set(current, forKey: pendingKey)
            return
        }

        let inboxSetId = inboxSet.id
        let existingCards = context.fetchWithErrorHandling(
            FetchDescriptor<Card>(predicate: #Predicate { $0.setId == inboxSetId })
        )

        for word in pending {
            let wordLower = word.lowercased()
            guard !existingCards.contains(where: { $0.en.lowercased() == wordLower }) else {
                log("[InboxDrain] skipped duplicate '\(word)'", level: .info)
                continue
            }
            let card = Card(en: word, item: "", setId: inboxSet.id)
            context.insert(card)
            log("[InboxDrain] inserted '\(word)' → Inbox")
        }

        context.saveWithErrorHandling()
        AnalyticsService.wordSavedFromShareExtension(wordCount: pending.count)
        log("[InboxDrain] saved \(pending.count) card(s) to Inbox", level: .info)
    }
}
