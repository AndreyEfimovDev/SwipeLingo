import SwiftUI

// MARK: - Custom Back Button
// Заменяет системную кнопку back на кастомную: chevron.left + title, цвет myBlue.
// Применяется на всех pushed view (NavigationLink destinations).
// Параметр title — название предыдущего экрана (как в стандартной iOS-кнопке).
//
// Использование:
//   .customBackButton("Pairs")   // в DynamicSetPlayerView
//   .customBackButton("Settings")   // в VoiceSettingsView

private struct CustomBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            if !title.isEmpty {
                                Text(title)
                                    .font(.body)
                            }
                        }
                        .foregroundStyle(Color.myColors.myBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
    }
}

extension View {
    func customBackButton(_ title: String = "") -> some View {
        modifier(CustomBackButtonModifier(title: title))
    }
}

// MARK: - Shadow

extension View {
    func myShadow() -> some View {
        self
            .shadow(color: Color.myColors.myShadow.opacity(0.3), radius: 8, x: 0, y: 0)
    }
}

extension View {
    func buttonRect(color: Color) -> some View {
        self
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(0.8), lineWidth: 1)
                
            }
    }
}

// MARK: - Conditional Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - FixedIconLabelStyle
// Standard for all Labels in vertical stacks.
// Fixes the icon width—text always starts on a single vertical line
// regardless of the SF Symbol width.
//
// Usage:
// Label("Title", systemImage: "icon").labelStyle(.fixedIcon)
// or on a container:
// VStack { ... }.labelStyle(.fixedIcon)

struct FixedIconLabelStyle: LabelStyle {
    var iconWidth: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .frame(width: iconWidth, alignment: .center)
            configuration.title
        }
    }
}

extension LabelStyle where Self == FixedIconLabelStyle {
    static var fixedIcon: FixedIconLabelStyle { .init() }
}
