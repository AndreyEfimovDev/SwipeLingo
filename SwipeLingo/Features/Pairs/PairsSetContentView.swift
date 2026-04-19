import SwiftUI

// MARK: - PairsSetContentView
//
// Static content view for a PairsSet shown in the library.
// Displays set description, then all pairs grouped by tag.
//
// Row layout per pair:
//   left + right  → one line, two columns  (right is always short)
//   description   → new line, full width   (definition / explanation)
//   sample        → new line, full width   (example sentence, italic)
//
// Paywall: first previewPairCount pairs (by original position) are free.

struct PairsSetContentView: View {

    let set: PairsSet

    @AppStorage("userPlan") private var userPlan: AccessTier = .free
    @State private var showPlans = false

    private let previewPairCount = 5
    private var isPaywalled: Bool { !userPlan.canAccess(set.accessTier) }

    // Map original position for paywall checks
    private var globalIndex: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: set.items.enumerated().map { ($0.element.id, $0.offset) })
    }

    // Groups preserving first-appearance order of tags
    private var groupedContent: [(tag: String, pairs: [Pair])] {
        var seenTags: [String] = []
        for pair in set.items where !seenTags.contains(pair.tag) {
            seenTags.append(pair.tag)
        }
        return seenTags.map { tag in (tag, set.items.filter { $0.tag == tag }) }
    }

    private var hasGroups: Bool {
        groupedContent.contains { !$0.tag.isEmpty }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── CEFR + description ────────────────────────
                metadataCard

                // ── Content ───────────────────────────────────
                if set.items.isEmpty {
                    emptyState
                } else {
                    contentTable
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .customBackButton("Pairs")
        .navigationTitle(set.title ?? "Pairs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPlans) { PlansView() }
    }

    // MARK: Metadata card (CEFR + expandable description)

    @ViewBuilder
    private var metadataCard: some View {
        let hasDesc = !(set.setDescription ?? "").isEmpty
        VStack(alignment: .leading, spacing: hasDesc ? 8 : 0) {
            CEFRBadgeView(level: set.cefrLevel)
                .font(.caption.weight(.semibold))

            if let desc = set.setDescription, !desc.isEmpty {
                ExpandableSection(text: desc, font: .subheadline, lineSpacing: 2, linesLimit: 3)
                    .foregroundStyle(Color.myColors.mySecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
        .padding(.horizontal, 16)
    }

    // MARK: Content table

    private var contentTable: some View {
        VStack(spacing: 0) {

            // Rows — grouped or flat
            if hasGroups {
                ForEach(groupedContent, id: \.tag) { group in
                    groupHeaderRow(group.tag, pairs: group.pairs)
                    Divider()
                    pairRows(group.pairs)
                }
            } else {
                pairRows(set.items)
            }
        }
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
        .padding(.horizontal, 16)
    }

    // MARK: Group header row
    //
    // Показывает название группы. Если первая пара группы имеет leftTitle/rightTitle —
    // добавляет заголовки колонок под названием группы.

    private func groupHeaderRow(_ tag: String, pairs: [Pair]) -> some View {
        let first = pairs.first
        let hasColumnTitles = first?.leftTitle != nil || first?.rightTitle != nil
        return VStack(alignment: .leading, spacing: 0) {
            if !tag.isEmpty {
                Text(tag.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, hasColumnTitles ? 4 : 8)
            }
            if hasColumnTitles {
                HStack(spacing: 0) {
                    if let left = first?.leftTitle {
                        Text(left)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.myColors.myGreen)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer()
                    }
                    if let right = first?.rightTitle {
                        Rectangle()
                            .fill(Color.myColors.myAccent.opacity(0.12))
                            .frame(width: 1, height: 12)
                        Text(right)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.myColors.myRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .background(Color.myColors.myAccent.opacity(0.04))
    }

    // MARK: Pair rows

    @ViewBuilder
    private func pairRows(_ pairs: [Pair]) -> some View {
        ForEach(Array(pairs.enumerated()), id: \.element.id) { localIndex, pair in
            let idx = globalIndex[pair.id] ?? 0
            if isPaywalled && idx >= previewPairCount {
                lockedPairRow(pair)
            } else {
                pairRow(pair)
            }

            // Divider — not after last in group, not before next group header
            let isLastInGroup = localIndex == pairs.count - 1
            if !isLastInGroup {
                Divider().padding(.leading, 16)
            }
        }
    }

    // MARK: Pair row
    //
    // left + right → two columns on one line
    // left only    → full width, medium weight
    // description  → new line, full width, secondary style
    // sample       → new line, full width, italic

    private func pairRow(_ pair: Pair) -> some View {
        VStack(alignment: .leading, spacing: 5) {

            // Line 1: left [+ right]
            if let right = pair.right {
                HStack(spacing: 0) {
                    Text(pair.left ?? "—")
                        .font(.body)
                        .foregroundStyle(Color.myColors.myAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle()
                        .fill(Color.myColors.myAccent.opacity(0.12))
                        .frame(width: 1)
                        .padding(.vertical, 2)

                    Text(right)
                        .font(.body)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.85))
                        .minimumScaleFactor(0.75)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                }
            } else {
                Text(pair.left ?? "—")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.myColors.myAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Line 2: description
            if let desc = pair.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Line 3: sample
            if let sample = pair.sample, !sample.isEmpty {
                Text(sample)
                    .font(.subheadline.italic())
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Locked pair row
    //
    // Левая часть (left) всегда видна — пользователь видит контент.
    // Правая часть: замок + "Upgrade to unlock" вместо значения.
    // Описание и пример скрыты.

    private func lockedPairRow(_ pair: Pair) -> some View {
        Button { showPlans = true } label: {
            HStack(spacing: 0) {
                Text(pair.left ?? "—")
                    .font(.body)
                    .foregroundStyle(Color.myColors.myAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.myColors.myAccent.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 2)

                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text("Upgrade to unlock")
                        .font(.subheadline)
                }
                .foregroundStyle(Color.myColors.myBlue.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty state

    private var emptyState: some View {
        Text("No pairs yet")
            .font(.subheadline)
            .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 32)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
    }
}
