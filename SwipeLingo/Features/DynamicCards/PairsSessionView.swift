import SwiftUI

// MARK: - PairsSessionView
// Последовательное воспроизведение сетов из PairsPile.
//
// Жизненный цикл:
//   • Один сет заполняет экран через DynamicSetPlayerView(onComplete:)
//   • По окончании сета снизу выезжает панель навигации:
//       [← Back]  [↺ Replay]  [Next Set →]   (не последний сет)
//       [← Back]  [↺ Replay]  [↺ Play Again] (последний сет) + "Pile complete"
//   • Next Set / Back: слайд-переход справа/слева
//   • Play Again: возврат к первому сету с переходом слева

struct PairsSessionView: View {

    let sets: [DynamicSet]
    let pileName: String

    @State private var currentIndex = 0
    @State private var setKey = UUID()
    @State private var goingForward = true
    @State private var isSetComplete = false

    private var isFirst: Bool { currentIndex == 0 }
    private var isLast:  Bool { currentIndex == sets.count - 1 }
    private var currentSet: DynamicSet { sets[currentIndex] }

    var body: some View {
        ZStack(alignment: .bottom) {
            DynamicSetPlayerView(set: currentSet, onComplete: {
                withAnimation { isSetComplete = true }
            }, autoStart: true)
            .id(setKey)
            .transition(slideTransition)

            if isSetComplete {
                navigationPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: setKey)
        .navigationTitle(currentSet.title ?? "Pairs")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Slide Transition

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading),
            removal:   .move(edge: goingForward ? .leading  : .trailing)
        )
    }

    // MARK: - Navigation Panel

    private var navigationPanel: some View {
        VStack(spacing: 0) {
            if isLast {
                Text("Pile complete")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
            }

            HStack(spacing: 0) {
                // Back — только если не первый сет
                if !isFirst {
                    Button {
                        goingForward = false
                        isSetComplete = false
                        currentIndex -= 1
                        setKey = UUID()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                            Text("Back")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 80, alignment: .leading)
                } else {
                    Spacer().frame(width: 80)
                }

                Spacer()

                // Replay — всегда
                Button {
                    isSetComplete = false
                    setKey = UUID()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline.weight(.medium))
                        Text("Replay")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Color.myColors.myBlue)
                }
                .buttonStyle(.plain)

                Spacer()

                // Next Set или Play Again
                if isLast {
                    Button {
                        goingForward = true
                        isSetComplete = false
                        currentIndex = 0
                        setKey = UUID()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Play Again")
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Color.myColors.myGreen)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 110, alignment: .trailing)
                } else {
                    Button {
                        goingForward = true
                        isSetComplete = false
                        currentIndex += 1
                        setKey = UUID()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Next Set")
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Color.myColors.myGreen)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 110, alignment: .trailing)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .myShadow()
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}
