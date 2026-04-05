import SwiftUI

// MARK: - AccessTierBadge
// Reusable badge for subscription plan indicators.
// Plans: Free (no badge) / Pro (gold gradient) / Pro+ (purple)
//
// Usage:
//   AccessTierBadge(tier: set.accessTier)

struct AccessTierBadge: View {
    let tier: AccessTier

    var body: some View {
        switch tier {
        case .free:
            EmptyView()
        case .pro:
            badge("PRO", gradient: true)
        case .proPlus:
            badge("PRO+", gradient: false)
        }
    }

    private func badge(_ label: String, gradient: Bool) -> some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                if gradient {
                    LinearGradient(
                        colors: [Color.myColors.myYellow, Color.myColors.myOrange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    Color.myColors.myPurple
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
