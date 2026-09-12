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

        // Сразу чистим очередь, чтобы второй переход в foreground не заимпортил
        // те же слова повторно, если сохранение SwiftData идёт медленно.
        defaults?.removeObject(forKey: pendingKey)

        let context = ModelContext(container)

        // Резолвим Inbox CardSet — он гарантированно существует после запуска
        // MockDataSeeder, но подстраховываемся guard'ом.
        let allSets = context.fetchWithErrorHandling(FetchDescriptor<CardSet>())
        guard let inboxSet = allSets.first(where: { $0.name == "Inbox" }) else {
            log("Inbox CardSet not found — re-queuing \(pending.count) word(s)", level: .warning)
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
                log("skipped duplicate '\(word)'", level: .info)
                continue
            }
            let card = Card(en: word, item: "", setId: inboxSet.id)
            context.insert(card)
            log("inserted '\(word)' → Inbox")
        }

        context.saveWithErrorHandling()
        AnalyticsFBService.wordSavedFromShareExtension(wordCount: pending.count)
        log("saved \(pending.count) card(s) to Inbox", level: .info)
    }
}
