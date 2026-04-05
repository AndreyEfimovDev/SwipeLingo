import SwiftUI
import SwiftData

// MARK: - DynamicCardsView
// Каталог English+ сетов. Простой List с карточками.
// При выборе → DynamicSetPlayerView.

struct DynamicCardsView: View {

    @Query(sort: \DynamicSet.createdAt, order: .reverse)
    private var sets: [DynamicSet]

    var body: some View {
        NavigationStack {
            Group {
                if sets.isEmpty {
                    emptyState
                } else {
                    setList
                }
            }
            .navigationTitle("English+")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - List

    private var setList: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    ForEach(sets) { set in
                        NavigationLink(destination: DynamicSetPlayerView(set: set)) {
                            DynamicSetRowView(set: set)
                        }
                        .buttonStyle(.plain)

                        if set.id != sets.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .myShadow()
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
            Text("No sets available")
                .font(.title3.bold())
                .foregroundStyle(Color.myColors.myAccent)
            Text("English+ sets will appear here once downloaded")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

// MARK: - DynamicSetRowView

private struct DynamicSetRowView: View {
    let set: DynamicSet

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(set.title ?? "Untitled")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent)

                // Subtitle
                if let subtitle = set.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                }

                // Column headers + item count
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

            // Access tier badge
            AccessTierBadge(tier: set.accessTier)

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

// MARK: - AccessTierBadge
// Reusable badge for subscription plan indicators.
// Plans: Free (no badge) / Go (purple→blue gradient) / Pro (yellow→orange gradient)
// NOTE: defined here; if needed elsewhere — add AccessTierBadge.swift to Xcode target.

struct AccessTierBadge: View {
    let tier: AccessTier
    var isSmall: Bool = false

    var body: some View {
        switch tier {
        case .free:
            EmptyView()
        case .go:
            badge("GO",  colors: [Color.myColors.myPurple, Color.myColors.myBlue])
        case .pro:
            badge("PRO", colors: [Color.myColors.myYellow, Color.myColors.myOrange])
        }
    }

    private func badge(_ label: String, colors: [Color]) -> some View {
        let gradient = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
        return Text(label)
            .font(isSmall ? .system(size: 7, weight: .bold) : .caption2.weight(.bold))
            .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            .padding(.horizontal, isSmall ? 4 : 6)
            .padding(.vertical,   isSmall ? 2 : 4)
            .frame(width: isSmall ? 26 : 38, alignment: .center)
            .background(gradient.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: isSmall ? 3 : 5))
            .overlay(
                RoundedRectangle(cornerRadius: isSmall ? 3 : 5)
                    .strokeBorder(gradient, lineWidth: 1)
            )
    }
}
