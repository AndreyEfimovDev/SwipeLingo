import SwiftUI

// MARK: - MainScreenToolbar
//
// Общий toolbar трёх главных экранов (FlashCardsView / PairsView / BooksView):
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
struct MainScreenToolbar: ToolbarContent {
    let appViewModel: AppViewModel
    let currentMode: AppViewModel.StudyMode

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { appViewModel.activeSheet = .settings } label: {
                Image(systemName: "gear")
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(AppViewModel.StudyMode.allCases.filter { $0 != currentMode }, id: \.self) { mode in
                    Button { appViewModel.studyMode = mode } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.icon).frame(width: 20)
                            Text("Switch to \(mode.label)")
                        }
                    }
                }
                Divider()
                Button { appViewModel.activeSheet = .statistics } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.line.uptrend.xyaxis").frame(width: 20)
                        Text("Statistics")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }
}
