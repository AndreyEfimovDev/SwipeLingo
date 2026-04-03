import Foundation

// MARK: - AccessTier
// Контролирует доступ к контенту в зависимости от плана подписки пользователя.
// Применяется к CardSet и DynamicSet.
// Детали планов (Free / Pro / ProPlus) — в Plans.docx.

enum AccessTier: String, Codable, CaseIterable {
    case free       // бесплатный контент, доступен всем
    case pro        // требует подписки Pro ($20/год)
    case proPlus    // требует подписки ProPlus ($40/год)
}
