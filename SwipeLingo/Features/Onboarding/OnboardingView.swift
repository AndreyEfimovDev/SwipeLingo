import SwiftUI

// MARK: - OnboardingView
// Координатор онбординга. Управляет шагами и анимацией перехода.
// Шаги:
//   0 — intro
//   1 — выбор языка (с предупреждением о постоянстве)
//   2 — ввод имени
//   3 — выбор уровня CEFR
//   4 — подтверждение настроек → в приложение

struct OnboardingView: View {

    var onComplete: () -> Void

    @State private var step: Int = 0
    @State private var goingForward = true

    private let totalSteps = 5

    var body: some View {
        ZStack {
            Color.myColors.myBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Навигационная строка
                navBar

                // Контент шага
                ZStack {
                    switch step {
                    case 0:
                        OnboardingIntroView { next() }
                            .transition(stepTransition)
                    case 1:
                        OnboardingLanguageView { next() }
                            .transition(stepTransition)
                    case 2:
                        OnboardingNameView(onNext: { next() }, onBack: { back() })
                            .transition(stepTransition)
                    case 3:
                        OnboardingLevelView(onNext: { next() }, onBack: { back() })
                            .transition(stepTransition)
                    default:
                        OnboardingConfirmView(onComplete: onComplete, onBack: { back() })
                            .transition(stepTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
            }
        }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack {
            // Back — скрыт на intro (0), language (1) и финальном экране (confirm имеет свою кнопку)
            if step > 1 && step < totalSteps - 1 {
                Button { back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.myColors.myBlue)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()

            // Dots — только для шагов настройки (1–3), не на intro и финале
            if step > 0 && step < totalSteps - 1 {
                progressDots
            }

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    // Dots показывают шаги 1–3 (язык, имя, уровень) — всего 3 точки
    private var progressDots: some View {
        let setupStep = step - 1  // 0, 1, 2 для шагов 1, 2, 3
        return HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i <= setupStep
                          ? Color.myColors.myBlue
                          : Color.myColors.myAccent.opacity(0.2))
                    .frame(width: i == setupStep ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: step)
            }
        }
    }

    // MARK: - Navigation

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading),
            removal:   .move(edge: goingForward ? .leading  : .trailing)
        )
        .combined(with: .opacity)
    }

    private func next() {
        goingForward = true
        step += 1
    }

    private func back() {
        goingForward = false
        step -= 1
    }
}
