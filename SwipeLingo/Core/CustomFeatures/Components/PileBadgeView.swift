import SwiftUI

// MARK: - PileBadgeView
// Капсула с именем активного Pile вверху экрана (Cards/Pairs) — тап открывает
// Library соответствующего раздела. Вынесен из CardsView/PairsView — оба экрана
// использовали идентичную разметку, различались только заголовок/состояние/действие.
//
// Использование:
//   PileBadgeView(title: hasActivePile ? name : "All Cards", isActive: hasActivePile) {
//       appViewModel.activeSheet = .cardsLibrary
//   }

struct PileBadgeView: View {
    let title: String
    /// Выбран ли конкретный Pile (а не дефолтное "All Cards"/"All Sets") — влияет
    /// только на цвет заголовка (ярче, если Pile реально выбран).
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.myColors.myAccent)
//                    .foregroundStyle(
//                        isActive
//                            ? Color.myColors.myAccent.opacity(0.75)
//                            : Color.myColors.myAccent.opacity(0.35)
//                    )
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.35))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.myColors.myBackground, in: Capsule())
            .myShadow()
        }
        .buttonStyle(.plain)
    }
}
