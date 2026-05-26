import SwiftUI

// MARK: - AdminSection

enum AdminSection: String, CaseIterable, Identifiable {
    case cardsCollections
    case pairsCollections
    case books

    var id: String { label }

    var label: String {
        switch self {
        case .cardsCollections: "Cards"
        case .pairsCollections: "Pairs"
        case .books:            "Books"
        }
    }

    var icon: String {
        switch self {
        case .cardsCollections: "rectangle.stack"
        case .pairsCollections: "square.grid.2x2"
        case .books:            "book.closed"
        }
    }

    var collectionType: CollectionType? {
        switch self {
        case .cardsCollections: .cards
        case .pairsCollections: .pairs
        case .books:            nil
        }
    }
}

// MARK: - ContentView

struct ContentView: View {

    @Environment(AdminStore.self) private var store

    @State private var selectedSection:     AdminSection? = .cardsCollections
    @State private var selectedCollectionId: String?
    @State private var selectedCardSetId:    String?
    @State private var selectedPairsSetId:   String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            if let section = selectedSection {
                switch section {
                case .books:
                    BooksListView()
                default:
                    if let type = section.collectionType {
                        CollectionsListView(
                            type: type,
                            selectedCollectionId: $selectedCollectionId
                        )
                    }
                }
            } else {
                ContentUnavailableView("Select a section", systemImage: "sidebar.left")
            }
        } detail: {
            if selectedSection == .books {
                ContentUnavailableView("Select a book", systemImage: "book.closed")
            } else {
                detailView
            }
        }
        // Сброс выбранного сета при смене коллекции или раздела
        .onChange(of: selectedCollectionId) { _, _ in
            selectedCardSetId  = nil
            selectedPairsSetId = nil
        }
        .onChange(of: selectedSection) { _, _ in
            selectedCardSetId  = nil
            selectedPairsSetId = nil
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detailView: some View {
        if let collectionId = selectedCollectionId, let section = selectedSection {
            switch section.collectionType {
            case .cards:
                if let setId = selectedCardSetId {
                    let setName = store.cardSets.first { $0.id == setId }?.name ?? ""
                    CardsListView(setId: setId, setName: setName) {
                        selectedCardSetId = nil
                    }
                } else {
                    CardSetsListView(collectionId: collectionId,
                                     selectedSetId: $selectedCardSetId)
                }
            case .pairs:
                if let setId = selectedPairsSetId {
                    let setName = store.pairsSets.first { $0.id == setId }?.title ?? "Untitled"
                    PairsListView(setId: setId, setName: setName) {
                        selectedPairsSetId = nil
                    }
                } else {
                    PairsSetsListView(collectionId: collectionId,
                                      selectedSetId: $selectedPairsSetId)
                }
            case nil:
                ContentUnavailableView("Select a collection", systemImage: "rectangle.stack")
            }
        } else {
            ContentUnavailableView("Select a collection", systemImage: "rectangle.stack")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(AdminSection.allCases, selection: $selectedSection) { section in
            Label(section.label, systemImage: section.icon)
                .tag(section)
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        .navigationTitle("SwipeLingo")
    }
}
