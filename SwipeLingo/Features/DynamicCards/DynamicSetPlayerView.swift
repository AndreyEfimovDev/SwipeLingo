import SwiftUI

// MARK: - DynamicSetPlayerView
// Воспроизведение одного DynamicSet — показ пар элементов с анимацией.
// Поддерживает DisplayMode (.sequential / .parallel) из модели сета.
// Поддерживает AnimationMode (.manual / .automatic) из пользовательских настроек.
// TODO: реализовать UI воспроизведения сета.

struct DynamicSetPlayerView: View {
    let set: DynamicSet

    @AppStorage("dynamicAnimationMode") private var defaultAnimationMode: AnimationMode = .manual
    @State private var animationMode: AnimationMode = .manual
    @State private var currentPairIndex: Int = 0
    @State private var revealedStep: Int = 0    // для .sequential: 0=left, 1=right

    var body: some View {
        NavigationStack {
            Text(set.title ?? "English+")
                .font(.largeTitle)
                .foregroundStyle(Color.myColors.myAccent)
                .navigationTitle(set.title ?? "English+")
                .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            animationMode = defaultAnimationMode
        }
    }
}
