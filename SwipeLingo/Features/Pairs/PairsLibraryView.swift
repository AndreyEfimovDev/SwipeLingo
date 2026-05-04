import SwiftUI
import SwiftData
import FirebaseCore

// MARK: - PairsLibraryView
// Управление PairsPiles и просмотр всех PairsSets.
//
// PILES — список пайлов:
//   • По умолчанию виден только активный пайл (или "No active pile").
//   • Если пайлов > 1 — кнопка "All piles (n)" разворачивает список.
//   • Тап на кружок → активировать пайл.
//   • Синяя кнопка карандаша → редактировать.
//   • Context menu → удалить.
// SETS — все доступные сеты → NavigationLink → PairsSetContentView.

struct PairsLibraryView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    @Query(sort: \PairsSet.createdAt, order: .reverse)    private var allSets:         [PairsSet]
    @Query(sort: \PairsPile.createdAt, order: .reverse)   private var allPiles:        [PairsPile]
    @Query(filter: #Predicate<Collection> { $0.typeRaw == "pairs" },
           sort: \Collection.createdAt)                   private var pairsCollections: [Collection]

    @AppStorage("nativeLanguage") private var nativeLangRaw: String = ""
    @Query private var profiles: [UserProfile]

    @State private var showAllPiles = false
    @State private var pileSheet: PairsPileSheet?
    @State private var isSyncing = false

    // MARK: - Grouping helpers

    private var userLevel: CEFRLevel { profiles.first?.cefrLevel ?? .c2 }

    private func sets(for collection: Collection) -> [PairsSet] {
        allSets.filter { $0.collectionId == collection.id && $0.cefrLevel <= userLevel }
    }

    /// Только коллекции с хотя бы одним сетом — скрываем пустые (кратковременно
    /// появляются во время sync пока cleanup ещё не удалил их).
    private var visiblePairsCollections: [Collection] {
        pairsCollections.filter { !sets(for: $0).isEmpty }
    }

    /// Сеты без коллекции или с неизвестным collectionId
    private var orphanedSets: [PairsSet] {
        let knownIds = Set(visiblePairsCollections.map(\.id))
        return allSets.filter { set in
            guard let colId = set.collectionId else { return true }
            return !knownIds.contains(colId)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                pilesSection
                setsSection
            }
            .padding(.vertical, 16)
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .navigationTitle("Pairs Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.myColors.myBlue)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isSyncing {
                    ProgressView()
                        .tint(Color.myColors.myBlue)
                } else {
                    Button {
                        Task { await syncContent() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundStyle(Color.myColors.myBlue)
                    }
                }
            }
        }
        .sheet(item: $pileSheet) { mode in
            switch mode {
            case .new:          PairsPileBuilderView(editingPile: nil)
            case .edit(let p):  PairsPileBuilderView(editingPile: p)
            }
        }
    }

    // MARK: - Piles Section

    private var pilesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PILES")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Button { pileSheet = .new } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.myColors.myBlue)
                }
                .buttonStyle(.borderless)
            }
            .foregroundStyle(Color.myColors.myAccent)
            .padding(.horizontal, 32)

            if allPiles.isEmpty {
                Text("No piles yet — tap + to create one")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .background(Color.myColors.myBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .myShadow()
                    .padding(.horizontal, 16)
            } else {
                let activePile  = allPiles.first(where: { $0.isActive })
                let sortedPiles = allPiles.sorted { $0.name.lowercased() < $1.name.lowercased() }
                let showToggle  = allPiles.count > 1

                VStack(spacing: 0) {
                    if showAllPiles {
                        ForEach(Array(sortedPiles.enumerated()), id: \.element.id) { idx, pile in
                            pileRow(pile)
                            if idx < sortedPiles.count - 1 {
                                Divider().padding(.leading, 44)
                            }
                        }
                    } else {
                        if let pile = activePile {
                            pileRow(pile)
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "circle")
                                    .font(.title3)
                                    .foregroundStyle(Color.myColors.myAccent.opacity(0.35))
                                Text("No active pile")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.myColors.myAccent.opacity(0.55))
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                    }

                    if showToggle {
                        Divider().padding(.leading, 44)
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { showAllPiles.toggle() }
                        } label: {
                            HStack {
                                Text(showAllPiles ? "Show less" : "All piles (\(allPiles.count))")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.myColors.myBlue)
                                Spacer()
                                Image(systemName: showAllPiles ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.myColors.myBlue)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.myColors.myBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .myShadow()
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func pileRow(_ pile: PairsPile) -> some View {
        HStack(spacing: 10) {
            Button { activatePile(pile) } label: {
                Image(systemName: pile.isActive ? "checkmark.circle" : "circle")
                    .foregroundStyle(pile.isActive ? Color.myColors.myGreen : Color.myColors.myAccent.opacity(0.8))
                    .font(.title3)
                    .animation(.spring(duration: 0.2), value: pile.isActive)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 3) {
                Text(pile.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(Color.myColors.myAccent)
                let sets   = PairsPileService().sets(for: pile, from: allSets)
                let count  = sets.count
                let pairs  = sets.reduce(0) { $0 + $1.items.count }
                Text("\(count) \(count == 1 ? "set" : "sets") (\(pairs))")
                    .font(.caption)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.7))
            }

            Spacer(minLength: 0)

            Button { pileSheet = .edit(pile) } label: {
                Image(systemName: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myBlue)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                context.delete(pile)
                context.saveWithErrorHandling()
            } label: {
                Label("Delete Pile", systemImage: "trash")
            }
        }
    }

    // MARK: - Sets Section

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SETS")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .padding(.horizontal, 32)

            if allSets.isEmpty {
                Text("No sets available")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .background(Color.myColors.myBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .myShadow()
                    .padding(.horizontal, 16)
            } else if visiblePairsCollections.isEmpty {
                // Нет коллекций с сетами — плоский список (резервный вариант)
                flatSetsBlock(allSets)
            } else {
                // Сгруппировано по коллекциям
                ForEach(visiblePairsCollections) { collection in
                    collectionSetBlock(collection)
                }
                // Сеты без коллекции
                if !orphanedSets.isEmpty {
                    flatSetsBlock(orphanedSets)
                }
            }
        }
    }

    // MARK: - Collection Set Block

    @ViewBuilder
    private func collectionSetBlock(_ collection: Collection) -> some View {
        let items = sets(for: collection)

        VStack(spacing: 0) {
            // Collection header
            HStack(spacing: 0) {
                Label(collection.name, systemImage: collection.icon ?? "folder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent)
                    .labelStyle(.fixedIcon)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.myColors.myAccent.opacity(0.04))

            if items.isEmpty {
                Divider().padding(.leading, 16)
                Text("No sets yet")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ForEach(items) { set in
                    Divider().padding(.leading, 16)
                    NavigationLink(destination: PairsSetContentView(set: set)) {
                        LibrarySetRow(set: set)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
        .padding(.horizontal, 16)
    }

    // MARK: - Flat Sets Block (no collection)

    @ViewBuilder
    private func flatSetsBlock(_ items: [PairsSet]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { set in
                NavigationLink(destination: PairsSetContentView(set: set)) {
                    LibrarySetRow(set: set)
                }
                .buttonStyle(.plain)
                if set.id != items.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func syncContent() async {
        isSyncing = true
        defer { isSyncing = false }
        let language = NativeLanguage(rawValue: nativeLangRaw) ?? .russian
        let level    = profiles.first?.cefrLevel ?? .c2
        await FirestoreImportService().syncFromFirestore(into: context, language: language, upToLevel: level)
    }

    private func activatePile(_ pile: PairsPile) {
        for p in allPiles { p.isActive = false }
        pile.isActive = true
        context.saveWithErrorHandling()
    }
}

// MARK: - PairsPileSheet

private enum PairsPileSheet: Identifiable {
    case new
    case edit(PairsPile)

    var id: String {
        switch self {
        case .new:          return "new"
        case .edit(let p):  return p.id.uuidString
        }
    }
}

// MARK: - LibrarySetRow

private struct LibrarySetRow: View {
    let set: PairsSet

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .top, spacing: 2) {
                let count = set.items.count
                HStack(spacing: 0) {
                    Text(set.title ?? "Untitled")
                        .font(.body)
                    if count > 0 {
                        Text(" (\(count))")
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                    }
                }
                AccessTierBadge(tier: set.accessTier)
                    .offset(y: -4)
            }

            Spacer()

            CEFRBadgeView(level: set.cefrLevel)
                .font(.caption.weight(.semibold))
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.myColors.myBlue)
        }
        .foregroundStyle(Color.myColors.myAccent)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
