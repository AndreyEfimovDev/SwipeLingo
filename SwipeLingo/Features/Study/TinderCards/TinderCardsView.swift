import SwiftUI
import SwiftData

// MARK: - TinderCardsView

struct TinderCardsView: View {

    @Environment(\.modelContext) private var context
    @AppStorage("studyDirection") private var studyDirection = "EN→RU"
    @State private var viewModel: TinderCardsViewModel
    @State private var lookupCard: Card?

    private let swipeThreshold: CGFloat = 110
    private let pileTagsLine: String
    /// Drives which field appears on the front face (EN→RU = false, RU→EN = true)
    private var isReversed: Bool { studyDirection == "RU→EN" }

    init(cards: [Card], contextLabels: [UUID: String] = [:], pileTagsLine: String = "",
         onDone: (() -> Void)? = nil) {
        _viewModel = State(
            initialValue: TinderCardsViewModel(cards: cards, contextLabels: contextLabels, onDone: onDone)
        )
        self.pileTagsLine = pileTagsLine
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                if viewModel.isDone {
                    doneContentView
                } else {
                    cardStack
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 460)

            // Pile tags line — e.g. "Academic Words · Grammar (12 cards)"
            if !pileTagsLine.isEmpty && !viewModel.isDone {
                Text(pileTagsLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }

            Spacer(minLength: 0)

            if !viewModel.isDone {
                progressBar
                    .padding(.bottom, 8)
                srsButtonsRow
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .opacity(viewModel.isFlipped ? 1 : 0)
                    .offset(y: viewModel.isFlipped ? 0 : 20)
                    .animation(.spring(duration: 0.35, bounce: 0.2), value: viewModel.isFlipped)
            } else {
                doneActionsView
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
        .background(Color(.systemBackground))
        .animation(.spring(duration: 0.3), value: viewModel.currentIndex)
        .animation(.spring(duration: 0.3), value: viewModel.isFlipped)
        .animation(.spring(duration: 0.4), value: viewModel.isDone)
        .sheet(item: $lookupCard) { card in
            DictionaryLookupView(card: card)
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        ProgressView(
            value: Double(max(0, viewModel.cards.count - viewModel.remaining)),
            total: Double(max(1, viewModel.cards.count))
        )
        .tint(.accentColor)
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        ZStack {
            // Background cards animate in real-time as the top card is dragged:
            // each card scales and rises toward the position of the card in front of it.
            let dragProgress = min(1.0, abs(viewModel.dragOffset.width) / swipeThreshold)

            ForEach([2, 1], id: \.self) { offset in
                let idx = viewModel.currentIndex + offset
                if idx < viewModel.cards.count {
                    // Animate each card toward the position of the card in front of it.
                    // offset=1 animates from (scale 0.95, y +20) → (1.0, y 0) as top card is dragged.
                    // offset=2 animates from (scale 0.90, y +40) → (0.95, y +20) in cascade.
                    let step: CGFloat = 0.05
                    let yStep: CGFloat = 20.0
                    let baseScale     = 1.0 - CGFloat(offset) * step
                    let targetScale   = 1.0 - CGFloat(offset - 1) * step
                    let scale         = baseScale + (targetScale - baseScale) * dragProgress
                    let baseYOffset   = CGFloat(offset) * yStep
                    let targetYOffset = CGFloat(offset - 1) * yStep
                    let yOffset       = baseYOffset + (targetYOffset - baseYOffset) * dragProgress
                    cardPlaceholder
                        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                        .scaleEffect(scale)
                        .offset(y: yOffset)
                }
            }

            // Top interactive card — new card springs up from stack position (scale 0.96→1.0)
            // No opacity fade: feels like physically lifting the top card off the pile.
            if let card = viewModel.currentCard {
                topCard(card)
                    .id(viewModel.currentIndex)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96),
                        removal: .identity
                    ))
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
        let frontText = isReversed ? card.item : card.en
        return VStack(spacing: 12) {
            Spacer()
            Text(frontText)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)

            Spacer()
            Text("Tap to flip")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
    }

    private func cardBack(_ card: Card) -> some View {
        let backText    = isReversed ? card.en   : card.item
        let sampleBack  = isReversed ? card.sampleEN.first  : card.sampleItem.first
        let sampleFront = isReversed ? card.sampleItem.first : card.sampleEN.first
        return VStack(spacing: 16) {
            Spacer()
            Text(backText)
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)

            if sampleFront != nil || sampleBack != nil {
                Divider().padding(.horizontal, 32)
                VStack(spacing: 6) {
                    if let sample = sampleFront {
                        Text(sample)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    if let sample = sampleBack {
                        Text(sample)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
            }

            // Dictionary lookup — only shown in EN→RU mode (English word on front)
            if !isReversed {
                Button {
                    lookupCard = card
                } label: {
                    Label("Look up in dictionary", systemImage: "book.pages")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }

            Spacer()
        }
    }

    // MARK: - Placeholder (background cards)
    // Same white fill as the top card — depth is conveyed by scale + shadow, not colour.

    private var cardPlaceholder: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(.systemBackground))
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
            srsButton(title: "Forgot", color: .red,   rating: .again)
            srsButton(title: "Hard",  color: .orange, rating: .hard)
            srsButton(title: "Easy",  color: .green,  rating: .easy)
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

    // MARK: - Done: content (inside 460pt ZStack)

    private var doneContentView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("All cards reviewed!")
                .font(.title.bold())
            HStack(spacing: 28) {
                VStack(spacing: 3) {
                    Text("\(viewModel.dueTomorrowCount)")
                        .font(.title2.bold())
                    Text("due tomorrow")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                    .frame(height: 36)
                VStack(spacing: 3) {
                    Text("\(viewModel.dueIn3DaysCount)")
                        .font(.title2.bold())
                    Text("due in 3 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    // MARK: - Done: actions (replaces SRS buttons row)

    private var doneActionsView: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) { viewModel.restart() }
            } label: {
                Text("Repeat all")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.2)) { viewModel.restartDue() }
                } label: {
                    Text("Only due")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.secondary.opacity(0.1))
                        .foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.onDone?()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.secondary.opacity(0.1))
                        .foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
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
            .fill(Color(.systemBackground))
            .frame(maxWidth: .infinity)
            .frame(height: 420)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    if let container = try? ModelContainer(for: Card.self, configurations: config) {
        let ctx = container.mainContext
        let setId = UUID()
        let card1 = Card(en: "Serendipity", item: "счастливая случайность",
                         sampleEN: ["What a serendipity to meet you here."],
                         sampleItem: ["Какая счастливая случайность встретить тебя здесь."],
                         setId: setId)
        let card2 = Card(en: "Ephemeral", item: "мимолётный", setId: setId)
        let card3 = Card(en: "Melancholy", item: "меланхолия", setId: setId)
        let _ = [card1, card2, card3].map { ctx.insert($0) }
        TinderCardsView(
            cards: [card1, card2, card3],
            contextLabels: [setId: "Advanced · IELTS"]
        )
        .modelContainer(container)
    }
}
