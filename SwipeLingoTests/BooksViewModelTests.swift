import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - BooksViewModelTests
//
// BooksViewModel.syncBooks:
//   • вызывает внедрённый источник каталога (а не создаёт Firestore-сервис сам)
//   • повторный вызов во время идущего синка игнорируется

@MainActor
final class BooksViewModelTests: XCTestCase {

    func testSyncBooks_CallsInjectedCatalog() async throws {
        let catalog = CountingCatalog()
        let vm = BooksViewModel(catalog: catalog)

        await vm.syncBooks(context: try makeContext())

        XCTAssertEqual(catalog.callCount, 1)
        XCTAssertFalse(vm.isSyncing)
    }

    func testSyncBooks_WhileSyncing_SecondCallIgnored() async throws {
        let catalog = CountingCatalog(delay: .milliseconds(200))
        let vm = BooksViewModel(catalog: catalog)
        let context = try makeContext()

        let first = Task { await vm.syncBooks(context: context) }
        await waitUntil { vm.isSyncing }
        await vm.syncBooks(context: context)
        await first.value

        XCTAssertEqual(catalog.callCount, 1)
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: Book.self, configurations: config))
    }
}

/// Подменный источник каталога: считает вызовы, по желанию «синхронизируется» с задержкой.
private final class CountingCatalog: BookCatalogSyncing {
    private(set) var callCount = 0
    private let delay: Duration?

    init(delay: Duration? = nil) {
        self.delay = delay
    }

    func syncBooks(into context: ModelContext) async {
        callCount += 1
        if let delay { try? await Task.sleep(for: delay) }
    }
}
