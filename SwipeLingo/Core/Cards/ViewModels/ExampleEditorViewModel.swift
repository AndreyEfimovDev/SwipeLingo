import Foundation

// MARK: - ExampleEditorViewModel
//
// Логика шита примеров карточки (ExampleEditorSheet): какие примеры можно удалить и попарное
// удаление «пример + перевод». У карточки две группы примеров:
//   • основные (sampleEN/sampleItem) — у пользовательской карточки их пишет AddEditCardView,
//     у облачной они приходят из Firestore;
//   • добавленные со словаря (userSampleEN/userSampleItem) — DictionaryLookupView.
// Основные примеры облачной карточки удалить нельзя: следующий Firestore-синк вернул бы их обратно.
// Переводы сопоставляются по индексу внутри своей группы, а не по общему списку.
// Работает с локальными копиями массивов — карточка меняется только в `apply(to:)` (по Save).

@Observable
final class ExampleEditorViewModel {

    /// Строка списка примеров.
    struct Row: Identifiable, Equatable {
        enum Group { case card, dictionary }

        let group: Group
        /// Индекс внутри своей группы.
        let index: Int
        let en: String
        let translation: String?
        let isRemovable: Bool

        var id: String { (group == .card ? "card-" : "dictionary-") + String(index) }
    }

    private(set) var sampleEN: [String]
    private(set) var sampleItem: [String]
    private(set) var userSampleEN: [String]
    private(set) var userSampleItem: [String]

    /// Можно ли удалять основные примеры — только у пользовательской карточки.
    private let canRemoveCardSamples: Bool
    private let original: [[String]]

    /// - Parameter isUserCard: карточка из пользовательского сета (`CardSet.isUserCreated`).
    init(sampleEN: [String], sampleItem: [String],
         userSampleEN: [String], userSampleItem: [String],
         isUserCard: Bool) {
        self.sampleEN = sampleEN
        self.sampleItem = sampleItem
        self.userSampleEN = userSampleEN
        self.userSampleItem = userSampleItem
        self.canRemoveCardSamples = isUserCard
        self.original = [sampleEN, sampleItem, userSampleEN, userSampleItem]
    }

    /// Создаёт ViewModel по текущим примерам карточки.
    convenience init(card: Card, isUserCard: Bool) {
        self.init(sampleEN: card.sampleEN, sampleItem: card.sampleItem,
                  userSampleEN: card.userSampleEN, userSampleItem: card.userSampleItem,
                  isUserCard: isUserCard)
    }

    // MARK: State

    /// Все примеры для отображения: сначала основные, потом добавленные со словаря.
    var rows: [Row] {
        makeRows(group: .card, en: sampleEN, items: sampleItem, isRemovable: canRemoveCardSamples)
            + makeRows(group: .dictionary, en: userSampleEN, items: userSampleItem, isRemovable: true)
    }

    /// Есть ли в списке примеры, которые удалить нельзя (для подписи под списком).
    var hasLockedRows: Bool { rows.contains { !$0.isRemovable } }

    var hasChanges: Bool {
        [sampleEN, sampleItem, userSampleEN, userSampleItem] != original
    }

    // MARK: Actions

    /// Удаляет пример вместе с его переводом. Неудаляемые строки игнорируются.
    func delete(_ row: Row) {
        guard row.isRemovable else { return }
        switch row.group {
        case .card:
            remove(at: row.index, en: &sampleEN, items: &sampleItem)
        case .dictionary:
            remove(at: row.index, en: &userSampleEN, items: &userSampleItem)
        }
    }

    /// Записывает отредактированные примеры в карточку (сохранение контекста — на вызывающей стороне).
    func apply(to card: Card) {
        if canRemoveCardSamples {
            card.sampleEN = sampleEN
            card.sampleItem = sampleItem
        }
        card.userSampleEN = userSampleEN
        card.userSampleItem = userSampleItem
    }

    // MARK: Private

    private func makeRows(group: Row.Group, en: [String], items: [String], isRemovable: Bool) -> [Row] {
        en.indices.map { i in
            let translation = i < items.count && !items[i].isEmpty ? items[i] : nil
            return Row(group: group, index: i, en: en[i], translation: translation, isRemovable: isRemovable)
        }
    }

    private func remove(at index: Int, en: inout [String], items: inout [String]) {
        guard en.indices.contains(index) else { return }
        en.remove(at: index)
        if index < items.count { items.remove(at: index) }
    }
}
