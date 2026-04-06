import SwiftUI
import SwiftData

// MARK: - PairsLibraryView
// Управление PairsPiles и просмотр всех DynamicSets.
//
// PILES — список пайлов:
//   • По умолчанию виден только активный пайл (или "No active pile").
//   • Если пайлов > 1 — кнопка "All piles (n)" разворачивает список.
//   • Тап на кружок → активировать пайл.
//   • Синяя кнопка карандаша → редактировать.
//   • Context menu → удалить.
// SETS — все доступные сеты → NavigationLink → DynamicSetPlayerView.

struct PairsLibraryView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \DynamicSet.createdAt, order: .reverse)  private var allSets: [DynamicSet]
    @Query(sort: \PairsPile.createdAt, order: .reverse)   private var allPiles: [PairsPile]

    @State private var showAllPiles  = false
    @State private var pileSheet: PairsPileSheet?

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
        VStack(alignment: .leading, spacing: 6) {
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
            } else {
                VStack(spacing: 0) {
                    ForEach(allSets) { set in
                        NavigationLink(destination: DynamicSetPlayerView(set: set)) {
                            LibrarySetRow(set: set)
                        }
                        .buttonStyle(.plain)

                        if set.id != allSets.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color.myColors.myBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .myShadow()
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Actions

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
    let set: DynamicSet

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 4) {
                    Text(set.title ?? "Untitled")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.myColors.myAccent)
                    AccessTierBadge(tier: set.accessTier, isSmall: true)
                        .offset(y: -3)
                }

                if let subtitle = set.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                }

                HStack(spacing: 6) {
                    if let left = set.leftTitle, let right = set.rightTitle {
                        Text("\(left) → \(right)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.myColors.myBlue)
                    }
                    let count = set.items.count
                    if count > 0 {
                        Text("·")
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                        Text("\(count) \(count == 1 ? "pair" : "pairs")")
                            .font(.caption)
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
