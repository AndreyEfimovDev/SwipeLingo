import SwiftUI
import SwiftData

// MARK: - DynamicCardsView
// Каталог English+ сетов (Dynamic Cards).
// Отдельный экран, не связан с TinderCards.
// TODO: реализовать UI каталога сетов с фильтрацией по AccessTier.

struct DynamicCardsView: View {
    @State private var viewModel = DynamicCardsViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Text("English+")
                .font(.largeTitle)
                .foregroundStyle(Color.myColors.myAccent)
                .navigationTitle("English+")
        }
        .onAppear {
            viewModel.loadSets(context: modelContext)
        }
    }
}
