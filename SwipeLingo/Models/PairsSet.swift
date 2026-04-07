import Foundation
import SwiftData

// MARK: - PairsSet
// Контент формата Pairs — сравнение уровней (B2↔C1, Basic↔Advanced).
// Создаётся командой, хранится в Firebase Firestore.
// Локально сохраняется в SwiftData, синхронизируется через CloudKit.
//
// items хранятся как JSON String (itemsJSON) для совместимости с CloudKit:
// CloudKit поддерживает только примитивные типы и Data/String, не Codable-структуры напрямую.

@Model
final class PairsSet {
    var id: UUID
    var title: String?
    var subtitle: String?
    var leftTitle: String?          // название левой колонки  ("B2", "Basic")
    var rightTitle: String?         // название правой колонки ("C1", "Advanced")
    var displayModeRaw: String      // DisplayMode.rawValue — хранится как String (CloudKit-safe)
    var accessTierRaw: String       // AccessTier.rawValue   — хранится как String (CloudKit-safe)
    var itemsJSON: String           // JSON-encoded [Pair] — хранится как String (CloudKit-safe)
    var createdAt: Date

    // MARK: SRS fields (SM-2) — оценка всего сета целиком
    var dueDate:      Date   = Date.distantFuture  // новый сет не в Due до первой оценки
    var interval:     Int    = 1
    var easeFactor:   Double = 2.5
    var repetitions:  Int    = 0
    var lastReviewed: Date   = Date.distantPast

    // MARK: Computed wrappers

    var displayMode: DisplayMode {
        get { DisplayMode(rawValue: displayModeRaw) ?? .parallel }
        set { displayModeRaw = newValue.rawValue }
    }

    var accessTier: AccessTier {
        get { AccessTier(rawValue: accessTierRaw) ?? .free }
        set { accessTierRaw = newValue.rawValue }
    }

    var items: [Pair] {
        get {
            guard let data = itemsJSON.data(using: .utf8),
                  let pairs = try? JSONDecoder().decode([Pair].self, from: data)
            else { return [] }
            return pairs
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8)
            else { itemsJSON = "[]"; return }
            itemsJSON = json
        }
    }

    // MARK: Init

    init(
        id: UUID = UUID(),
        title: String? = nil,
        subtitle: String? = nil,
        leftTitle: String? = nil,
        rightTitle: String? = nil,
        displayMode: DisplayMode = .parallel,
        accessTier: AccessTier = .free,
        items: [Pair] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.leftTitle = leftTitle
        self.rightTitle = rightTitle
        self.displayModeRaw = displayMode.rawValue
        self.accessTierRaw = accessTier.rawValue
        self.itemsJSON = (try? String(data: JSONEncoder().encode(items), encoding: .utf8)) ?? "[]"
        self.createdAt = createdAt
    }
}

// MARK: - DisplayMode
// Порядок появления элементов пары в UI.
// Задаётся автором сета при создании контента.
// Если right == nil в паре — показывается только left (в любом режиме).

enum DisplayMode: String, Codable, CaseIterable {
    case sequential // left → right → новая строка → left → right...
    case parallel   // left + right одновременно → новая строка
}

// MARK: - AnimationMode
// Способ перехода к следующему элементу сета.
// НЕ хранится в модели — это пользовательская настройка:
//   @AppStorage("pairsAnimationMode") — значение по умолчанию (Settings)
//   @State var animationMode в PairsSetPlayerView — может переключаться во время просмотра

enum AnimationMode: String, Codable, CaseIterable {
    case manual    // пользователь тапает для показа следующего элемента
    case automatic // авто-показ с задержкой между элементами
}

// MARK: - Pair
// Одна строка контента: левый и правый элемент.
// Оба optional — если right == nil, показывается только left.

struct Pair: Codable, Identifiable {
    var id: UUID = UUID()
    var left: PairSide?
    var right: PairSide?
}

// MARK: - PairSide
// Один элемент пары: текст.

struct PairSide: Codable {
    var text: String?
}
