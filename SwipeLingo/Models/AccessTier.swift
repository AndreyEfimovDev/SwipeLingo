import Foundation

// MARK: - AccessTier
// Контролирует доступ к контенту в зависимости от плана подписки пользователя.
// Применяется к CardSet и DynamicSet.
// Планы: Free / Go / Pro

enum AccessTier: String, Codable, CaseIterable {
    case free  // бесплатный контент, доступен всем
    case go    // план Go  — бейдж "GO"  (myPurple → myBlue gradient)
    case pro   // план Pro — бейдж "PRO" (myYellow → myOrange gradient)
}
