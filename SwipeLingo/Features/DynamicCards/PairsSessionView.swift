import SwiftUI
import SwiftData

// MARK: - PairsSessionView
// Последовательное воспроизведение сетов из PairsPile.
//
// Жизненный цикл одного сета:
//   1. Воспроизведение → DynamicSetPlayerView(autoStart: true, onComplete:)
//   2. Завершение → SRS-панель (если SRS включён): Forgot / Hard / Easy
//   3. Навигация: [← Back] [↺ Replay] [Next Set →] / [↺ Play Again] + "Pile complete"
//
// SRS: оценка всего сета целиком через SRSService.evaluate(set:rating:).

struct PairsSessionView: View {

    let sets: [DynamicSet]
    let pileName: String

    @Environment(\.modelContext) private var context
    @AppStorage("srsEnabled") private var srsEnabled: Bool = true

    @State private var currentIndex  = 0
    @State private var setKey        = UUID()
    @State private var goingForward  = true
    @State private var isSetComplete = false
    @State private var isRated       = false   // SRS оценка выставлена для текущего сета
    /// Pile-level режим — читается из UserDefaults синхронно при создании вью,
    /// чтобы DynamicSetPlayerView получил правильное значение с первого рендера.
    /// Next Set всегда использует это значение, локальные изменения внутри сета не влияют.
    @State private var sessionMode: AnimationMode = {
        let raw = UserDefaults.standard.string(forKey: "dynamicAnimationMode") ?? ""
        return AnimationMode(rawValue: raw) ?? .manual
    }()

    private var isFirst: Bool { currentIndex == 0 }
    private var isLast:  Bool { currentIndex == sets.count - 1 }
    private var currentSet: DynamicSet { sets[currentIndex] }

    /// SRS-панель нужна если SRS включён и оценка ещё не выставлена
    private var showRatingPanel: Bool { srsEnabled && !isRated }

    var body: some View {
        ZStack(alignment: .bottom) {
            DynamicSetPlayerView(
                set: currentSet,
                onComplete: { withAnimation { isSetComplete = true } },
                autoStart: true,
                initialAnimationMode: sessionMode
            )
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
            if showRatingPanel {
                ratingPanel
            } else {
                if isLast {
                    Text("Pile complete")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }
                navButtons
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .myShadow()
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    // MARK: - SRS Rating Panel

    private var ratingPanel: some View {
        VStack(spacing: 10) {
            Text("How well did you know this set?")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .padding(.top, 14)

            HStack(spacing: 10) {
                ratingButton("Forgot", color: Color.myColors.myRed)   { applyRating(.again) }
                ratingButton("Hard",   color: Color.myColors.myOrange) { applyRating(.hard)  }
                ratingButton("Easy",   color: Color.myColors.myGreen)  { applyRating(.easy)  }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    private func ratingButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color.opacity(0.12))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func applyRating(_ rating: SRSRating) {
        SRSService().evaluate(set: currentSet, rating: rating)
        context.saveWithErrorHandling()
        withAnimation { isRated = true }
    }

    // MARK: - Nav Buttons

    private var navButtons: some View {
        HStack(spacing: 0) {
            // Back
            if !isFirst {
                Button {
                    goingForward = false
                    nextSet(index: currentIndex - 1)
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

            // Replay
            Button {
                isSetComplete = false
                isRated = false
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
                    nextSet(index: 0)
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
                    nextSet(index: currentIndex + 1)
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

    // MARK: - Helpers

    private func nextSet(index: Int) {
        isSetComplete = false
        isRated = false
        currentIndex = index
        setKey = UUID()
    }
}
