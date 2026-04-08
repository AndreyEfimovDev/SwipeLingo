import SwiftUI

// MARK: - AdminSection

enum AdminSection: String, CaseIterable, Identifiable {
    case cardsCollections = "Cards"
    case pairsCollections = "Pairs"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cardsCollections: "rectangle.stack"
        case .pairsCollections: "square.grid.2x2"
        }
    }

    var collectionType: CollectionType {
        switch self {
        case .cardsCollections: .cards
        case .pairsCollections: .pairs
        }
    }
}

// MARK: - ContentView

struct ContentView: View {

    @State private var selectedSection: AdminSection? = .cardsCollections
    @State private var selectedCollectionId: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            if let section = selectedSection {
                CollectionsListView(
                    type: section.collectionType,
                    selectedCollectionId: $selectedCollectionId
                )
            } else {
                ContentUnavailableView("Select a section", systemImage: "sidebar.left")
            }
        } detail: {
            ContentUnavailableView("Select a collection", systemImage: "rectangle.stack")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(AdminSection.allCases, selection: $selectedSection) { section in
            Label(section.rawValue, systemImage: section.icon)
                .tag(section)
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        .navigationTitle("SwipeLingo")
    }
}
