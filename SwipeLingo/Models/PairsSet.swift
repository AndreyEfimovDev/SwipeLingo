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
    var setDescription: String?      // optional longer description shown in content view
    var cefrLevelRaw:    String      // CEFRLevel.rawValue    — хранится как String (CloudKit-safe)
    var accessTierRaw:   String      // AccessTier.rawValue   — хранится как String (CloudKit-safe)
    var deployStatusRaw: String      // SetDeployStatus.rawValue — хранится как String (CloudKit-safe)
    var itemsJSON: String            // JSON-encoded [Pair] — хранится как String (CloudKit-safe)
    var collectionId: UUID?          // nil = локальный/мок; UUID = Firebase-коллекция
    var updatedAt: Date = Date.epoch // обновляется Admin Tool при публикации
    var createdAt: Date

    // MARK: SRS fields (SM-2) — оценка всего сета целиком
    var dueDate:      Date   = Date.farFuture  // новый сет не в Due до первой оценки
    var interval:     Int    = 1
    var easeFactor:   Double = 2.5
    var repetitions:  Int    = 0
    var lastReviewed: Date   = Date.epoch

    // MARK: Computed wrappers

    var cefrLevel: CEFRLevel {
        get { CEFRLevel(rawValue: cefrLevelRaw) ?? .b2 }
        set { cefrLevelRaw = newValue.rawValue }
    }

    var accessTier: AccessTier {
        get { AccessTier(rawValue: accessTierRaw) ?? .free }
        set { accessTierRaw = newValue.rawValue }
    }

    var deployStatus: SetDeployStatus {
        get { SetDeployStatus(rawValue: deployStatusRaw) ?? .new }
        set { deployStatusRaw = newValue.rawValue }
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
        setDescription: String? = nil,
        cefrLevel: CEFRLevel = .b2,
        accessTier: AccessTier = .free,
        deployStatus: SetDeployStatus = .new,
        items: [Pair] = [],
        collectionId: UUID? = nil,
        updatedAt: Date = .epoch,
        createdAt: Date = .now
    ) {
        self.id              = id
        self.title           = title
        self.setDescription  = setDescription
        self.cefrLevelRaw    = cefrLevel.rawValue
        self.accessTierRaw   = accessTier.rawValue
        self.deployStatusRaw = deployStatus.rawValue
        self.itemsJSON       = (try? String(data: JSONEncoder().encode(items), encoding: .utf8)) ?? "[]"
        self.collectionId    = collectionId
        self.updatedAt       = updatedAt
        self.createdAt       = createdAt
    }
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
//
// Единица контента в PairsSet (SwiftData-версия, хранится как JSON в PairsSet.itemsJSON).
// Зеркалит FSPair из FirestoreModels — см. там полный комментарий по семантике полей.

struct Pair: Codable, Identifiable {
    var id:          UUID        = UUID()
    var left:        String?
    var right:       String?
    var description: String?
    var sample:      String?
    var tag:         String      = ""
    var leftTitle:   String?                      // заголовок левой колонки (classic / pairs+sample)
    var rightTitle:  String?                      // заголовок правой колонки (classic / pairs+sample)
    var displayMode: DisplayMode = .parallel      // parallel / sequential (на уровне группы)

    init(id: UUID = UUID(),
         left: String? = nil,
         right: String? = nil,
         description: String? = nil,
         sample: String? = nil,
         tag: String = "",
         leftTitle: String? = nil,
         rightTitle: String? = nil,
         displayMode: DisplayMode = .parallel) {
        self.id          = id
        self.left        = left
        self.right       = right
        self.description = description
        self.sample      = sample
        self.tag         = tag
        self.leftTitle   = leftTitle
        self.rightTitle  = rightTitle
        self.displayMode = displayMode
    }
}
