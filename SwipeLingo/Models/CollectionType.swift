import Foundation

// MARK: - CollectionType
// Тип коллекции определяет какой контент в ней хранится.
// Задаётся при создании в Admin Tool, не меняется после публикации.

enum CollectionType: String, Codable, CaseIterable {
    case cards  // содержит CardSets → Cards (EN↔Native)
    case pairs  // содержит PairsSets → Pairs (EN↔EN)
}
