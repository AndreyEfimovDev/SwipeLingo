import Foundation

enum ShuffleMethod: String, Codable, CaseIterable {
    case random
    case sequential
    case prioritized
}
