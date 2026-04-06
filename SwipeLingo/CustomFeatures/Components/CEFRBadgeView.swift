import SwiftUI

// MARK: - CEFRBadgeView
// Universal CEFR level badge. Pass nil to hide (e.g. user-created sets have no level).
//
// Usage:
//   CEFRBadgeView(level: cardSet.cefrLevel)   // developer set
//   CEFRBadgeView(level: nil)                 // user-created set — renders nothing

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
