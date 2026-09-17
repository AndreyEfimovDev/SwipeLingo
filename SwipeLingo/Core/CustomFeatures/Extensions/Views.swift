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
                                    .font(.headline)
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

// MARK: - Sheet Navigation Bar
// Nav bar для модальных .sheet на mySheetBackground (не .fullScreenCover — те используют
// штатный .navigationTitle, глобальный UIAppearanceConfigurator красит их title в myAccent
// без проблем). .toolbarBackground(_:for:) — единственный способ перекрасить бар конкретного
// экрана в mySheetBackground (иначе он останется чёрным из глобального UIAppearance) — но
// SwiftUI при этом создаёт для бара отдельную per-instance UINavigationBarAppearance, которая
// НЕ наследует titleTextAttributes из appearance-прокси в UIAppearanceConfigurator: заголовок
// откатывается на системный белый вместо myAccent. Явный Text в .principal — обходит это,
// цвет не зависит от того, чья именно UINavigationBarAppearance сейчас активна.
//
// Использование (вместо .navigationTitle + .navigationBarTitleDisplayMode + вручную
// .toolbarBackground(mySheetBackground)):
//   .sheetNavigationBar("Examples")

private struct SheetNavigationBarModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.myColors.myAccent)
                        .lineLimit(1)
                }
            }
            .toolbarBackground(Color.myColors.mySheetBackground, for: .navigationBar)
    }
}

extension View {
    func sheetNavigationBar(_ title: String) -> some View {
        modifier(SheetNavigationBarModifier(title: title))
    }
}

// MARK: - Nav Bar Icon Style
// Единый вид для всех иконок-кнопок в nav bar (gear, chevron-back вне .customBackButton,
// +, arrow.clockwise, "..." и т.д.) — по стандарту "Иконки-ссылки" из CLAUDE.md: плоская
// иконка без фона/подложки, только размер + цвет (myBlue активная / myAccent.opacity(0.8)
// неактивная по умолчанию). Применяется на Image внутри Button ИЛИ Menu label — оба
// принимают произвольный View, модификатор не завязан на конкретный тип контрола.
//
// Использование:
//   Image(systemName: "gear").navBarIconStyle()                          // неактивная (по умолчанию)
//   Image(systemName: "chevron.left").navBarIconStyle(color: .myBlue)    // активная
//
// На iOS 26 сам ToolbarItem всё равно оборачивает контент в системную glass-капсулу
// независимо от того, есть ли у нас свой фон — чтобы иконка была ДЕЙСТВИТЕЛЬНО плоской,
// добавляй `.hiddenSharedBackgroundIfAvailable()` на сам ToolbarItem.

extension View {
    func navBarIconStyle(color: Color = Color.myColors.myBlue) -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
    }
}

// MARK: - Hidden Shared Background (iOS 26 Liquid Glass)
// На iOS 26 каждый ToolbarItem сам получает стеклянную glass-капсулу — она накладывается
// на кнопки с собственной ручной обводкой (NavBarButtonForSheet) и ломает их вид. Системный
// модификатор `.sharedBackgroundVisibility(.hidden)`, убирающий её, доступен только с iOS 26 —
// таргет проекта iOS 18+, поэтому оборачиваем в #available вместо прямого вызова.
//
// Использование (вместо ToolbarItem(...) { ... }.sharedBackgroundVisibility(.hidden)):
//   ToolbarItem(...) { ... }.hiddenSharedBackgroundIfAvailable()

extension ToolbarContent {
    @ToolbarContentBuilder
    func hiddenSharedBackgroundIfAvailable() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
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
