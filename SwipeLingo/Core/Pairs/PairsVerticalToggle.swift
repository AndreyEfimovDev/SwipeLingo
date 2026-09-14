import SwiftUI

// MARK: - PairsVerticalToggle
// Вертикальный switch с лейблами сверху и снизу.
// isOn = true  → круг у верхнего лейбла (topLabel активен)
// isOn = false → круг у нижнего лейбла (bottomLabel активен)

struct PairsVerticalToggle: View {

    let topLabel:    String
    let bottomLabel: String
    let activeColor: Color
    @Binding var isOn: Bool
    var onToggle: ((Bool) -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Text(topLabel)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? activeColor : Color.myColors.myAccent.opacity(0.4))

            PairsSwitch(isOn: $isOn, activeColor: activeColor, onToggle: onToggle)
                .frame(width: 44, height: 76)

            Text(bottomLabel)
                .font(.subheadline.weight(!isOn ? .semibold : .regular))
                .foregroundStyle(!isOn ? Color.myColors.myAccent.opacity(0.75) : Color.myColors.myAccent.opacity(0.4))
        }
    }
}

// MARK: - PairsSwitch
// Вертикальный капсуло-переключатель.
// Адаптирован из горизонтального Switch (P280_SwitchComponent).

private struct PairsSwitch: View {

    @Binding var isOn: Bool
    var activeColor: Color
    var onToggle: ((Bool) -> Void)? = nil

    @GestureState private var isTapped = false

    var backgroundColor: Color {
        isOn ? activeColor.opacity(0.85) : Color.myColors.myAccent.opacity(0.12)
    }

    var handleColor: Color {
        isOn ? .white : Color.myColors.myAccent.opacity(0.75)
    }

    var gesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTapped) { _, state, _ in state = true }
            .onEnded { _ in
                // withAnimation только для пользовательского тапа —
                // программные изменения (selectDefaultMode) не анимируются
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isOn.toggle()
                }
                onToggle?(isOn)
            }
    }

    var body: some View {
        GeometryReader { geo in
            let gap = geo.size.width * 0.1
            // isOn = true → handle сверху (у активного topLabel)
            ZStack(alignment: isOn ? .top : .bottom) {
                Capsule()
                    .fill(backgroundColor)
                Capsule()
                    .fill(handleColor)
                    .padding(gap)
                    .frame(height: handleHeight(geo.size))
                    .shadow(
                        color: Color.black.opacity(0.25),
                        radius: gap * 0.6,
                        x: 0, y: 0
                    )
            }
        }
        .gesture(gesture)
        // Только isTapped анимируется глобально (stretch-эффект при нажатии)
        // isOn НЕ анимируется глобально — анимация только через withAnimation в gesture
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isTapped)
    }

    /// Handle вытягивается при нажатии, как в оригинале.
    private func handleHeight(_ size: CGSize) -> CGFloat {
        let w = size.width
        let h = size.height
        return isTapped ? w + (h - w) * 0.3 : w
    }
}
