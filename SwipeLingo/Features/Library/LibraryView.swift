import SwiftUI
import SwiftData

// MARK: - LibraryView
// Root of the Library tab: Collections → Sets → Cards (NavigationStack)

struct LibraryView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @State private var viewModel = LibraryViewModel()

    var body: some View {
        NavigationStack {
            List {
                collectionsSection
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.isShowingAddCollection = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.isShowingAddCollection) {
                AddCollectionView()
            }
            .overlay {
                if collections.isEmpty { emptyState }
            }
        }
    }

    // MARK: - Collections Section

    private var collectionsSection: some View {
        Section {
            ForEach(regularCollections) { collection in
                NavigationLink {
                    CollectionDetailView(collection: collection)
                } label: {
                    CollectionRow(collection: collection)
                }
            }
            .onDelete { offsets in
                deleteCollections(at: offsets, from: regularCollections)
            }
        } header: {
            Text("Collections")
        }
    }

    // Inbox is shown at top with a distinct icon; other collections follow
    private var regularCollections: [Collection] {
        let inbox = collections.filter { $0.name == "Inbox" }
        let rest  = collections.filter { $0.name != "Inbox" }
        return inbox + rest
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No collections yet")
                .font(.title3.bold())
            Text("Tap + to create your first collection")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Deletion

    private func deleteCollections(at offsets: IndexSet, from list: [Collection]) {
        for index in offsets {
            context.delete(list[index])
        }
        try? context.save()
    }
}

// MARK: - CollectionRow

private struct CollectionRow: View {
    let collection: Collection

    var body: some View {
        Label(collection.name, systemImage: collection.icon ?? "folder")
    }
}
