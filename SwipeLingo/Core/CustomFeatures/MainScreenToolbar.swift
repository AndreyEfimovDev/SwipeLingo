import SwiftUI

// MARK: - MainScreenToolbar
//
// Общий toolbar трёх главных экранов (CardsView / PairsView / BooksView):
// шестерёнка настроек слева + меню "..." справа (переключение на два других
// таба + Statistics). Был продублирован по коду во всех трёх — вынесен сюда.
//
// "Switch to X" пункты меню строятся из AppViewModel.StudyMode.allCases,
// исключая currentMode — иконка/подпись берутся из уже существующих
// StudyMode.icon/.label, а не дублируются здесь заново.

/// Toolbar-контент для одного из трёх главных экранов. Использование:
/// `.toolbar { MainScreenToolbar(appViewModel: appViewModel, currentMode: .cards) }`
/// Экраны с дополнительными toolbar-кнопками (например `BooksView`) добавляют
/// свой `ToolbarItem(placement: .topBarTrailing)` в тот же `.toolbar { }` —
/// до `MainScreenToolbar`, чтобы сохранить порядок (кнопка → меню "...").
///
/// `MainScreenToolbar` — `ToolbarContent`, не `View`, фон навигационного бара
/// сам не задаёт — используется глобальный стеклянный бар (transparent + blur),
/// настроенный в `UIAppearanceConfigurator`.
/// НЕ скрывать фон бара через `.toolbarBackground(.hidden, for: .navigationBar)` —
/// это убирает сам blur-материал; исторически `.hidden` на CardsView/PairsView/BooksView
/// давал на iOS 26 серые "плашки" сверху/снизу экрана (SettingsView бар никогда не
/// скрывал и проблемы не имел). Иконки — `.navBarIconStyle()`, без своего фона.
/// Подробности — CLAUDE.md, "Navigation Bar и модальные окна".
struct MainScreenToolbar: ToolbarContent {
    let appViewModel: AppViewModel
    let currentMode: AppViewModel.StudyMode

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { appViewModel.activeSheet = .settings } label: {
                Image(systemName: "gear")
                    .navBarIconStyle(color: Color.myColors.myBlue)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                // Пункты меню — Label: меню рисует система (UIMenu) и берёт из SwiftUI только Label/Text+Image.
                // Цвет текста пунктов системный — foregroundStyle и tint его не меняют (проверено 2026-11-05).
                ForEach(AppViewModel.StudyMode.allCases.filter { $0 != currentMode }, id: \.self) { mode in
                    Button { appViewModel.studyMode = mode } label: {
                        Label("Switch to \(mode.label)", systemImage: mode.icon)
                    }
                }
                Divider()
                Button { appViewModel.activeSheet = .statistics } label: {
                    Label("Statistics", systemImage: "chart.line.uptrend.xyaxis")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .navBarIconStyle(color: Color.myColors.myBlue)
            }
        }
    }
}
