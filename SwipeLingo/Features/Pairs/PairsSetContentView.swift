import SwiftUI

// MARK: - PairsSetContentView
//
// Static content view for a PairsSet shown in the library.
// Displays the set description (if any), column headers,
// and all pairs as a scrollable table — no playback, no animation.
//
// Paywall: first previewPairCount pairs are free; the rest show a locked row.

struct PairsSetContentView: View {

    let set: PairsSet

    @AppStorage("userPlan") private var userPlan: AccessTier = .free
    @State private var showPlans = false

    private let previewPairCount = 5
    private var isPaywalled: Bool { !userPlan.canAccess(set.accessTier) }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── Description ───────────────────────────────
                if let desc = set.setDescription, !desc.isEmpty {
                    descriptionCard(desc)
                }

                // ── Content table ─────────────────────────────
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

    // MARK: Description card

    private func descriptionCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
    }

    // MARK: Content table

    private var contentTable: some View {
        VStack(spacing: 0) {
            // Column headers
            if set.leftTitle != nil || set.rightTitle != nil {
                columnHeaders
                Divider()
            }

            // Pairs
            ForEach(Array(set.items.enumerated()), id: \.element.id) { index, pair in
                if !isPaywalled || index < previewPairCount {
                    pairRow(pair: pair)
                } else {
                    lockedRow
                }
                if index < set.items.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
        .padding(.horizontal, 16)
    }

    // MARK: Column headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            if let left = set.leftTitle {
                Text(left)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.myColors.myGreen)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }

            Rectangle()
                .fill(Color.myColors.myAccent.opacity(0.12))
                .frame(width: 1, height: 14)

            if let right = set.rightTitle {
                Text(right)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.myColors.myRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Pair row

    private func pairRow(pair: Pair) -> some View {
        HStack(spacing: 0) {
            Text(pair.left?.text ?? "—")
                .font(.body)
                .foregroundStyle(Color.myColors.myAccent)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.myColors.myAccent.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 6)

            Text(pair.right?.text ?? "—")
                .font(.body)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: Locked row

    private var lockedRow: some View {
        Button { showPlans = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.3))
                Text("Upgrade to unlock")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myBlue.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
