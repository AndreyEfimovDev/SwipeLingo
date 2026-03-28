import SwiftUI
import SwiftData

// MARK: - CollectionDetailView
// Second level: list of CardSets inside a Collection.

struct CollectionDetailView: View {

    @Environment(\.modelContext) private var context
    let collection: Collection

    @Query(sort: \CardSet.createdAt) private var allSets: [CardSet]
    @State private var isShowingAddSet = false

    private var cardSets: [CardSet] {
        allSets.filter { $0.collectionId == collection.id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !cardSets.isEmpty {
                    setsSection
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingAddSet = true } label: {
                    Image(systemName: "plus")
                }
                .foregroundStyle(Color.myColors.myBlue)
            }
        }
        .sheet(isPresented: $isShowingAddSet) {
            AddCardSetView(collectionId: collection.id)
        }
        .overlay {
            if cardSets.isEmpty { emptyState }
        }
    }

    // MARK: - Sets Section

    private var setsSection: some View {
        VStack(spacing: 0) {
            ForEach(cardSets) { cardSet in
                NavigationLink {
                    CardSetDetailView(cardSet: cardSet, allowsEditing: collection.isUserCreated)
                } label: {
                    HStack {
                        Text(cardSet.name)
                            .font(.body)
                            .foregroundStyle(Color.myColors.myAccent)
                        Spacer()
                        if !collection.isUserCreated {
                            Text(cardSet.cefrLevel.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.myColors.mySecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.myColors.mySecondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.myColors.myBlue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        context.delete(cardSet)
                        try? context.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                if cardSet.id != cardSets.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
        .padding(.horizontal, 16)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 42))
            Text("No sets yet")
                .font(.title3.bold())
            Text("Tap + to add a set")
                .font(.subheadline)
        }
    }
}
