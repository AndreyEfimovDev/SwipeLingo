import SwiftUI

// MARK: - AccessTierBadge
// Reusable badge for subscription plan indicators.
// Plans: Free (no badge) / Go (purple→blue gradient) / Pro (yellow→orange gradient)
//
// Usage:
//   AccessTierBadge(tier: set.accessTier)            // regular size
//   AccessTierBadge(tier: set.accessTier, isSmall: true)  // superscript size

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
