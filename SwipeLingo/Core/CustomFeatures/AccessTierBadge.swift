import SwiftUI

// MARK: - AccessTierBadge
// Переиспользуемый бейдж для индикаторов плана подписки.
// Планы: Free (зелёный градиент) / Go (фиолетовый→синий градиент) / Pro (жёлтый→оранжевый градиент)
//
// Использование:
//   AccessTierBadge(tier: set.accessTier)            // обычный размер
//   AccessTierBadge(tier: set.accessTier, isSmall: true)  // уменьшенный размер

struct AccessTierBadge: View {
    let tier: AccessTier
    var isSmall: Bool = false

    var body: some View {
        switch tier {
        case .free:
            badge("FREE", colors: [Color.myColors.myGreen, Color.myColors.myGreen.opacity(0.6)])
        case .go:
            badge("GO",   colors: [Color.myColors.myPurple, Color.myColors.myBlue])
        case .pro:
            badge("PRO",  colors: [Color.myColors.myYellow, Color.myColors.myOrange])
        }
    }

    private func badge(_ label: String, colors: [Color]) -> some View {
        let gradient = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
        return Text(label)
            .font(isSmall ? .system(size: 7, weight: .bold) : .caption2.weight(.bold))
            .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            .padding(.horizontal, isSmall ? 4 : 6)
            .padding(.vertical,   isSmall ? 2 : 4)
            .background(gradient.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: isSmall ? 3 : 5))
            .overlay(
                RoundedRectangle(cornerRadius: isSmall ? 3 : 5)
                    .strokeBorder(gradient, lineWidth: 1)
            )
    }
}
