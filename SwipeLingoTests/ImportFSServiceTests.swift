import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - ImportFSServiceTests
//
// Покрывает `ImportFSService.applyRemoteContent(to:...)` — чистую логику апдейта уже
// существующей локальной карточки данными из Firestore, вынесенную отдельно от
// `syncFromFirestore` ради тестируемости без сети/Firebase (у ImportFSService нет
// протокола-обёртки для мока Firestore, см. AppViewModelTests — тот же приём для
// AppViewModel.levelIncrease).
//
// Главное, что здесь проверяется: card.status НЕ меняется при апдейте — мягко удалённая
// (.deleted) или изученная (.learnt) curated-карточка должна пережить sync без изменений.
// Новый статус "erased" не понадобился именно потому, что applyRemoteContent никогда не
// трогает status — это осознанный tombstone-инвариант, зафиксированный тестом, чтобы
// будущая правка (напр. "заодно синхронизировать status") не сломала его молча.

@MainActor
final class ImportFSServiceTests: XCTestCase {

    let service = ImportFSService()

    // MARK: - Helpers

    /// Свежий in-memory ModelContainer/Context на каждый тест — тот же паттерн, что в
    /// SRSServiceTests.
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Card.self, configurations: config)
        return ModelContext(container)
    }

    private func makeCard(context: ModelContext, status: CardStatus) -> Card {
        let card = Card(en: "old", item: "старое", setId: UUID())
        card.status = status
        context.insert(card)
        return card
    }

    // MARK: - status переживает апдейт независимо от исходного значения

    func testApplyRemoteContent_DeletedCard_StatusUnchanged() throws {
        let ctx  = try makeContext()
        let card = makeCard(context: ctx, status: .deleted)

        service.applyRemoteContent(
            to: card, en: "new", item: "новое",
            sampleEN: ["Sample"], sampleItem: ["Пример"],
            dictTranscription: "/nuː/", updatedAt: .now
        )

        XCTAssertEqual(card.status, .deleted)
    }

    func testApplyRemoteContent_LearntCard_StatusUnchanged() throws {
        let ctx  = try makeContext()
        let card = makeCard(context: ctx, status: .learnt)

        service.applyRemoteContent(
            to: card, en: "new", item: "новое",
            sampleEN: [], sampleItem: [],
            dictTranscription: "", updatedAt: .now
        )

        XCTAssertEqual(card.status, .learnt)
    }

    func testApplyRemoteContent_ActiveCard_StatusUnchanged() throws {
        let ctx  = try makeContext()
        let card = makeCard(context: ctx, status: .active)

        service.applyRemoteContent(
            to: card, en: "new", item: "новое",
            sampleEN: [], sampleItem: [],
            dictTranscription: "", updatedAt: .now
        )

        XCTAssertEqual(card.status, .active)
    }

    // MARK: - контентные поля реально обновляются

    func testApplyRemoteContent_UpdatesContentFields() throws {
        let ctx  = try makeContext()
        let card = makeCard(context: ctx, status: .active)
        let newUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        service.applyRemoteContent(
            to: card, en: "new", item: "новое",
            sampleEN: ["Sample"], sampleItem: ["Пример"],
            dictTranscription: "/nuː/", updatedAt: newUpdatedAt
        )

        XCTAssertEqual(card.en, "new")
        XCTAssertEqual(card.item, "новое")
        XCTAssertEqual(card.sampleEN, ["Sample"])
        XCTAssertEqual(card.sampleItem, ["Пример"])
        XCTAssertEqual(card.dictTranscription, "/nuː/")
        XCTAssertEqual(card.updatedAt, newUpdatedAt)
    }
}
