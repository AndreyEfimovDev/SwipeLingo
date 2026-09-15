import SwiftUI

// MARK: - Custom Back Button
// Заменяет системную кнопку back на кастомную: chevron.left + title, цвет myBlue.
// Применяется на всех pushed view (NavigationLink destinations).
// Параметр title — название предыдущего экрана (как в стандартной iOS-кнопке).
//
// Использование:
//   .customBackButton("Pairs")   // в PairsSetPlayerView
//   .customBackButton("Settings")   // в VoiceSettingsView
//   .customBackButton("", isHidden: editMode == .active)   // экран с Edit-режимом
//     (CardSetDetailView) — на время редактирования кнопку нужно СКРЫТЬ целиком (не просто
//     подвинуть), чтобы её место в topBarLeading занял, например, Select All: toolbar
//     допускает несколько ToolbarItem(.topBarLeading) одновременно — они располагаются
//     рядом, а не заменяют друг друга, так что без isHidden соседний Select All просто
//     сдвигал бы шеврон вправо, а не занимал его место.

private struct CustomBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var isHidden: Bool = false

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                if !isHidden {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 17, weight: .semibold))
                                if !title.isEmpty {
                                    Text(title)
                                        .font(.body)
                                        .lineLimit(1)
                                }
                            }
                            .fixedSize()
                            .foregroundStyle(Color.myColors.myBlue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
    }
}

extension View {
    func customBackButton(_ title: String = "", isHidden: Bool = false) -> some View {
        modifier(CustomBackButtonModifier(title: title, isHidden: isHidden))
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
// Стандарт для всех Label в вертикальных стеках.
// Фиксирует ширину иконки — текст всегда начинается на одной вертикальной линии,
// независимо от ширины SF Symbol.
//
// Использование:
// Label("Title", systemImage: "icon").labelStyle(.fixedIcon)
// или на контейнере:
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


// MARK: - TextInput Style

extension View {
    func textInputStyle(invalid: Bool = false) -> some View {
        self
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        invalid ? Color.myColors.myRed.opacity(0.6) : Color.myColors.myAccent.opacity(0.2),
                        lineWidth: invalid ? 1.5 : 1
                    )
            )
            .foregroundStyle(Color.myColors.myAccent)
    }
}
