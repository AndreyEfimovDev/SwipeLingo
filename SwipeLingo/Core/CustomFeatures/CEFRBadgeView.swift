import SwiftUI

// MARK: - CEFRBadgeView
// Универсальный бейдж CEFR-уровня. Передай nil, чтобы скрыть (напр. у пользовательских сетов уровня нет).
//
// Использование:
//   CEFRBadgeView(level: cardSet.cefrLevel)   // сет от разработчика
//   CEFRBadgeView(level: nil)                 // пользовательский сет — ничего не рендерит

struct CEFRBadgeView: View {
    let level: CEFRLevel?
    var body: some View {
        if let level {
            Text(level.displayCode)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.clear, in: .capsule)
                .overlay {
                    Capsule()
                        .stroke(level.color, lineWidth: 1)
                }
        }
    }
}
