import SwiftUI
import SwiftData

// MARK: - TinderCardsView

struct TinderCardsView: View {

    @Environment(\.modelContext) private var context
    @State private var viewModel: TinderCardsViewModel

    private let swipeThreshold: CGFloat = 110

    init(cards: [Card], contextLabels: [UUID: String] = [:]) {
        _viewModel = State(
            initialValue: TinderCardsViewModel(cards: cards, contextLabels: contextLabels)
        )
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal)
                .padding(.top, 16)

            Spacer(minLength: 0)

            ZStack {
                if viewModel.isDone {
                    doneView
                } else {
                    cardStack
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 460)

            Spacer(minLength: 0)

            if !viewModel.isDone {
                srsButtonsRow
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .opacity(viewModel.isFlipped ? 1 : 0)
                    .offset(y: viewModel.isFlipped ? 0 : 20)
                    .animation(.spring(duration: 0.35, bounce: 0.2), value: viewModel.isFlipped)
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.currentIndex)
        .animation(.spring(duration: 0.3), value: viewModel.isFlipped)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack {
            Text("\(viewModel.remaining) карточек")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            ProgressView(
                value: Double(max(0, viewModel.cards.count - viewModel.remaining)),
                total: Double(max(1, viewModel.cards.count))
            )
            .frame(width: 120)
            .tint(.accentColor)
        }
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        ZStack {
            // Background cards (index +2, +1) — shown behind for depth
            ForEach([2, 1], id: \.self) { offset in
                let idx = viewModel.currentIndex + offset
                if idx < viewModel.cards.count {
                    cardPlaceholder
                        .scaleEffect(1.0 - CGFloat(offset) * 0.04)
                        .offset(y: CGFloat(offset) * 10)
                        .opacity(0.6 - Double(offset) * 0.15)
                }
            }

            // Top interactive card
            if let card = viewModel.currentCard {
                topCard(card)
                    .zIndex(1)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Top Card

    private func topCard(_ card: Card) -> some View {
        FlippableCardView(
            isFlipped: viewModel.isFlipped,
            front: { cardFront(card) },
            back:  { cardBack(card)  }
        )
        .overlay(swipeColorOverlay)
        .offset(x: viewModel.dragOffset.width, y: viewModel.dragOffset.height * 0.15)
        .rotationEffect(viewModel.dragRotation)
        .gesture(dragGesture)
        .onTapGesture { viewModel.flip() }
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
    }

    // MARK: - Card Faces

    private func cardFront(_ card: Card) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(card.en)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)

            if !viewModel.currentContextLabel.isEmpty {
                Text(viewModel.currentContextLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Нажмите, чтобы перевернуть")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
    }

    private func cardBack(_ card: Card) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(card.item)
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)

            if !card.sampleEN.isEmpty || !card.sampleItem.isEmpty {
                Divider().padding(.horizontal, 32)
                VStack(spacing: 6) {
                    if let sample = card.sampleEN.first {
                        Text(sample)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    if let sample = card.sampleItem.first {
                        Text(sample)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Placeholder (background cards)

    private var cardPlaceholder: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.background.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 420)
    }

    // MARK: - Swipe Colour Overlay

    private var swipeColorOverlay: some View {
        let progress = viewModel.swipeProgress
        let color: Color = progress > 0 ? .green : .red
        let opacity = abs(progress) * 0.45
        return RoundedRectangle(cornerRadius: 24)
            .fill(color.opacity(opacity))
            .allowsHitTesting(false)
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                viewModel.dragOffset = value.translation
            }
            .onEnded { value in
                let dx = value.translation.width
                if dx > swipeThreshold {
                    withAnimation(.spring(duration: 0.35)) {
                        viewModel.dragOffset = CGSize(width: 600, height: dx * 0.3)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        viewModel.commitSwipe(direction: .right, context: context)
                    }
                } else if dx < -swipeThreshold {
                    withAnimation(.spring(duration: 0.35)) {
                        viewModel.dragOffset = CGSize(width: -600, height: dx * 0.3)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        viewModel.commitSwipe(direction: .left, context: context)
                    }
                } else {
                    withAnimation(.spring(duration: 0.4, bounce: 0.4)) {
                        viewModel.dragOffset = .zero
                    }
                }
            }
    }

    // MARK: - SRS Buttons

    private var srsButtonsRow: some View {
        HStack(spacing: 12) {
            srsButton(title: "Не знал", color: .red,    rating: .again)
            srsButton(title: "Сложно",  color: .orange, rating: .hard)
            srsButton(title: "Легко",   color: .green,  rating: .easy)
        }
    }

    private func srsButton(title: String, color: Color, rating: SRSRating) -> some View {
        Button {
            viewModel.evaluate(rating: rating, context: context)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(color.opacity(0.35), lineWidth: 1)
                )
        }
    }

    // MARK: - Done View

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Отлично!")
                .font(.title.bold())
            Text("Все карточки пройдены")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

// MARK: - FlippableCardView

private struct FlippableCardView<Front: View, Back: View>: View {

    let isFlipped: Bool
    @ViewBuilder let front: () -> Front
    @ViewBuilder let back:  () -> Back

    var body: some View {
        ZStack {
            // Front face: 0° → 180°
            cardShape
                .overlay(
                    front()
                        .rotation3DEffect(.degrees(isFlipped ? 180 : 0),
                                          axis: (x: 0, y: 1, z: 0),
                                          perspective: 0.5)
                )
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0),
                                  axis: (x: 0, y: 1, z: 0),
                                  perspective: 0.5)
                .opacity(isFlipped ? 0 : 1)

            // Back face: -180° → 0°
            cardShape
                .overlay(
                    back()
                        .rotation3DEffect(.degrees(isFlipped ? 0 : -180),
                                          axis: (x: 0, y: 1, z: 0),
                                          perspective: 0.5)
                )
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180),
                                  axis: (x: 0, y: 1, z: 0),
                                  perspective: 0.5)
                .opacity(isFlipped ? 1 : 0)
        }
        .animation(.spring(duration: 0.5, bounce: 0.15), value: isFlipped)
    }

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.background)
            .frame(maxWidth: .infinity)
            .frame(height: 420)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Card.self, configurations: config)
    let ctx = container.mainContext

    let setId = UUID()
    let card1 = Card(en: "Serendipity", item: "счастливая случайность",
                     sampleEN: ["What a serendipity to meet you here."],
                     sampleItem: ["Какая счастливая случайность встретить тебя здесь."],
                     setId: setId)
    let card2 = Card(en: "Ephemeral", item: "мимолётный", setId: setId)
    let card3 = Card(en: "Melancholy", item: "меланхолия", setId: setId)
    ctx.insert(card1); ctx.insert(card2); ctx.insert(card3)

    return TinderCardsView(
        cards: [card1, card2, card3],
        contextLabels: [setId: "Advanced · IELTS"]
    )
    .modelContainer(container)
}
