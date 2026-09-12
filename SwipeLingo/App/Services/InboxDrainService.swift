import Foundation
import SwiftData

// MARK: - InboxDrainService
//
// Читает слова, поставленные в очередь Share Extension через shared App Group
// UserDefaults, и вставляет их как Card в Inbox CardSet. Вынесен из SwipeLingoApp —
// это бизнес-логика (SwiftData-мутации, дедупликация), а не забота точки входа.

struct InboxDrainService {

    /// Разгружает очередь pending-слов (записанную SwipeLingoShare) в Inbox CardSet.
    /// No-op, если очередь пуста. Если Inbox CardSet не резолвится, или не удалось
    /// проверить дубли — слова возвращаются обратно в очередь, а не теряются.
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

        /// Возвращает слова обратно в начало очереди — используется при любом сбое,
        /// после которого продолжать разгрузку небезопасно (слова не должны теряться).
        func requeue(_ reason: String) {
            log("\(reason) — re-queuing \(pending.count) word(s)", level: .warning)
            var current = defaults?.stringArray(forKey: pendingKey) ?? []
            current.insert(contentsOf: pending, at: 0)
            defaults?.set(current, forKey: pendingKey)
        }

        let context = ModelContext(container)

        // Резолвим Inbox CardSet — он гарантированно существует после запуска
        // MockDataSeeder, но подстраховываемся guard'ом.
        let allSets = context.fetchWithErrorHandling(FetchDescriptor<CardSet>())
        guard let inboxSet = allSets.first(where: { $0.name == "Inbox" }) else {
            requeue("Inbox CardSet not found")
            return
        }

        let inboxSetId = inboxSet.id
        // Явный try/catch, а не fetchWithErrorHandling: та при сбое молча вернула бы
        // [], что здесь означало бы "дублей нет" и привело бы к повторной вставке
        // слов, уже лежащих в Inbox — безопаснее вернуть слова в очередь и повторить
        // при следующем foreground, чем создать дубль карточки.
        let existingCards: [Card]
        do {
            existingCards = try context.fetch(
                FetchDescriptor<Card>(predicate: #Predicate { $0.setId == inboxSetId })
            )
        } catch {
            ErrorManager.shared.handle(error, message: SwiftDataError.fetchFailed.message)
            requeue("Failed to check Inbox for duplicates")
            return
        }

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
