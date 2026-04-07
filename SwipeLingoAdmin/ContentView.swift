import SwiftUI

// MARK: - Sidebar Item

enum AdminSection: String, CaseIterable, Identifiable {
    case cardsCollections  = "Cards Collections"
    case pairsCollections  = "Pairs Collections"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cardsCollections: "rectangle.stack"
        case .pairsCollections: "square.grid.2x2"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {

    @State private var selectedSection: AdminSection? = .cardsCollections

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(AdminSection.allCases, selection: $selectedSection) { section in
            Label(section.rawValue, systemImage: section.icon)
                .tag(section)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        .navigationTitle("SwipeLingo Admin")
    }

    // MARK: Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .cardsCollections:
            CollectionsView(type: .cards)
        case .pairsCollections:
            CollectionsView(type: .pairs)
        case .none:
            Text("Select a section")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - CollectionsView (placeholder)

struct CollectionsView: View {

    let type: CollectionType

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: type == .cards ? "rectangle.stack" : "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(type == .cards ? "Cards Collections" : "Pairs Collections")
                .font(.title2.weight(.semibold))
            Text("Firebase not connected yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(type == .cards ? "Cards Collections" : "Pairs Collections")
    }
}
