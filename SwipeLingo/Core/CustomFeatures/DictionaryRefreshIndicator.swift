import SwiftUI

// MARK: - DictionaryRefreshIndicator
// Строка «что ещё догружается» на экранах словаря: контент уже виден, а полные определения
// от Merriam-Webster ещё в пути. Вынесена из DictionaryLookupView — та же строка нужна
// в BookWordLookupView (оба экрана на DictionaryLookupViewModel).
//
// Использование:
//   if let status = vm.refreshStatusText {
//       DictionaryRefreshIndicator(text: status)
//   }

struct DictionaryRefreshIndicator: View {
    /// Подпись у спиннера — `DictionaryLookupViewModel.refreshStatusText`.
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
