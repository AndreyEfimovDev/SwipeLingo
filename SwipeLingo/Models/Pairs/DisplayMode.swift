import Foundation

// MARK: - DisplayMode
// Порядок появления элементов пары в UI.
// Задаётся автором сета при создании контента.
// Если right == nil в паре — показывается только left (в любом режиме).

enum DisplayMode: String, Codable, CaseIterable {
    case sequential // left → right → новая строка → left → right...
    case parallel   // left + right одновременно → новая строка
}
