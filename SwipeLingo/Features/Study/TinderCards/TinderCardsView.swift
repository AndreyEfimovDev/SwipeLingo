import SwiftUI
import SwiftData

// MARK: - TinderCardsView

struct TinderCardsView: View {

    @Environment(\.modelContext)       private var context
    @Environment(\.verticalSizeClass)  private var verticalSizeClass
    @Environment(AppViewModel.self)    private var appViewModel
    @AppStorage("studyDirection")      private var studyDirection = "EN→Native"
    @State private var viewModel: TinderCardsViewModel
    @State private var lookupCard: Card?
    @State private var audioService  = AudioPlayerService()
    @State private var examplePageIndex: Int = 0

    private let swipeThreshold:   CGFloat = 110
    private let upSwipeThreshold: CGFloat = 100
    private let pileTagsLine: String

    private var isReversed:  Bool { studyDirection == "Native→EN" }
    private var isLandscape: Bool { verticalSizeClass == .compact }

    /// 0…1 upward-drag progress for trash animation. Zero when card is flipped.
    private var upSwipeProgress: Double {
        guard !viewModel.isFlipped,
              viewModel.dragOffset.height < -10,
              abs(viewModel.dragOffset.width) < 55 else { return 0 }
        return min(1.0, abs(Double(viewModel.dragOffset.height)) / Double(upSwipeThreshold))
    }

    init(cards: [Card],
         contextLabels: [UUID: String] = [:],
         pileTagsLine: String = "",
         onDone: (() -> Void)? = nil) {
        _viewModel   = State(initialValue: TinderCardsViewModel(
                                cards: cards,
                                contextLabels: contextLabels,
                                onDone: onDone))
        self.pileTagsLine = pileTagsLine
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLandscape { landscapeBody } else { portraitBody }
        }
        .background(Color(.systemBackground))
        .animation(.spring(duration: 0.3), value: viewModel.currentIndex)
        .animation(.spring(duration: 0.3), value: viewModel.isFlipped)
        .animation(.spring(duration: 0.4), value: viewModel.isDone)
        .sheet(item: $lookupCard) { DictionaryLookupView(card: $0) }
        .onDisappear { audioService.stop() }
        .onChange(of: viewModel.currentIndex) { _, _ in examplePageIndex = 0 }
    }

    // MARK: - Portrait

    private var portraitBody: some View {
        VStack(spacing: 0) {
            ZStack {
                if viewModel.isDone { doneFullCard } else { cardStack }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if !viewModel.isDone {
                progressStatsRow
            }
        }
    }

    // MARK: - Landscape

    private var landscapeBody: some View {
        HStack(spacing: 0) {
            landscapeStatsColumn
            Divider()
            ZStack {
                if viewModel.isDone { doneFullCard } else { cardStack }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        // System tab bar is already hidden by AppView in landscape
    }

    // MARK: - Landscape Stats Column

    private var landscapeStatsColumn: some View {
        let total   = viewModel.cards.count
        let learned = viewModel.learnedInSession
        let active  = total - learned
        return VStack(spacing: 0) {
            Spacer()
            statLabel("Learned", value: learned)
            Spacer()
            Text("\(total)").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            statLabel("Active", value: active)
            Spacer()
        }
        .frame(width: 56)
    }

    private func statLabel(_ title: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text("\(value)").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Portrait Stats Row

    private var progressStatsRow: some View {
        let total   = viewModel.cards.count
        let learned = viewModel.learnedInSession
        let active  = total - learned
        return HStack {
            Text("Active ").foregroundStyle(.tertiary)
            + Text("\(active)").foregroundStyle(.secondary).bold()
            Spacer()
            Text("\(total) cards").foregroundStyle(.tertiary)
            Spacer()
            Text("Learned ").foregroundStyle(.tertiary)
            + Text("\(learned)").foregroundStyle(.secondary).bold()
        }
        .font(.caption2)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Breadcrumb

    /// "Collection › Set" label for the *current* card — per-card, not pile-level.
    private var cardBreadcrumb: String {
        guard let card = viewModel.currentCard else { return "" }
        return viewModel.contextLabels[card.setId] ?? ""
    }

    @ViewBuilder
    private var breadcrumbRow: some View {
        let label = cardBreadcrumb
        if !label.isEmpty {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            Divider()
        }
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        ZStack {
            let dragProgress = min(1.0, abs(viewModel.dragOffset.width) / swipeThreshold)

            ForEach([2, 1], id: \.self) { offset in
                let idx = viewModel.currentIndex + offset
                if idx < viewModel.cards.count {
                    let step:        CGFloat = 0.05
                    let yStep:       CGFloat = -20.0
                    let baseScale    = 1.0 - CGFloat(offset) * step
                    let targetScale  = 1.0 - CGFloat(offset - 1) * step
                    let scale        = baseScale + (targetScale - baseScale) * dragProgress
                    let baseY        = CGFloat(offset) * yStep
                    let targetY      = CGFloat(offset - 1) * yStep
                    let yOffset      = baseY + (targetY - baseY) * dragProgress
                    Group {
                        if offset == 1 { nextCardPreview(viewModel.cards[idx]) }
                        else           { cardPlaceholder }
                    }
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                    .scaleEffect(scale)
                    .offset(y: yOffset)
                }
            }

            if let card = viewModel.currentCard {
                topCard(card)
                    .id(viewModel.currentIndex)
                    .transition(.asymmetric(insertion: .scale(scale: 0.96), removal: .identity))
                    .zIndex(1)
            }

            // Trash icon — upward drag on front face
            if upSwipeProgress > 0 {
                VStack {
                    ZStack {
                        Circle()
                            .fill(.red.opacity(0.12 * upSwipeProgress))
                            .frame(width: 72, height: 72)
                        Image(systemName: "trash.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.red)
                            .scaleEffect(0.7 + 0.5 * upSwipeProgress)
                    }
                    .opacity(upSwipeProgress)
                    .padding(.top, 12)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .zIndex(2)
            }
        }
    }

    // MARK: - Top Card

    private func topCard(_ card: Card) -> some View {
        let yOffset: CGFloat = viewModel.isFlipped ? 0 :
            (viewModel.dragOffset.height < -5
                ? viewModel.dragOffset.height
                : viewModel.dragOffset.height * 0.15)
        let scale = max(0.3, 1.0 - 0.5 * upSwipeProgress)

        return fullCardContainer(card)
            .overlay(swipeColorOverlay)
            .offset(x: viewModel.dragOffset.width, y: yOffset)
            .rotationEffect(viewModel.dragRotation)
            .scaleEffect(scale)
            .simultaneousGesture(dragGesture)
            .onTapGesture { viewModel.flipToBack() }
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
    }

    // MARK: - Full Card Container

    private func fullCardContainer(_ card: Card) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(Color(.systemBackground))
            if isLandscape {
                landscapeCardContent(card)
            } else {
                portraitCardContent(card)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func portraitCardContent(_ card: Card) -> some View {
        VStack(spacing: 0) {
            breadcrumbRow
            flipContent(card: card).frame(maxHeight: .infinity)
            // SRS pinned to bottom — always in layout, fades in after flip
            Divider()
            srsButtonsRow
                .padding(12)
                .opacity(viewModel.isFlipped ? 1 : 0)
                .allowsHitTesting(viewModel.isFlipped)
                .animation(.spring(duration: 0.35, bounce: 0.2), value: viewModel.isFlipped)
        }
    }

    private func landscapeCardContent(_ card: Card) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                breadcrumbRow
                flipContent(card: card).frame(maxHeight: .infinity)
            }
            // SRS column pinned to right — fades in after flip
            Divider()
            srsButtonsColumn
                .frame(width: 90)
                .opacity(viewModel.isFlipped ? 1 : 0)
                .allowsHitTesting(viewModel.isFlipped)
                .animation(.spring(duration: 0.35, bounce: 0.2), value: viewModel.isFlipped)
        }
    }

    // MARK: - Flip Content

    private func flipContent(card: Card) -> some View {
        ZStack {
            cardFront(card)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rotation3DEffect(.degrees(viewModel.isFlipped ? 180 : 0),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .opacity(viewModel.isFlipped ? 0 : 1)

            cardBack(card)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rotation3DEffect(.degrees(viewModel.isFlipped ? 0 : -180),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .opacity(viewModel.isFlipped ? 1 : 0)
        }
        .animation(.spring(duration: 0.5, bounce: 0.15), value: viewModel.isFlipped)
    }

    // MARK: - Card Front

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

    // MARK: - Card Back

    private func cardBack(_ card: Card) -> some View {
        let backLargeText = isReversed ? card.en   : card.item
        let backSmallText = isReversed ? card.item : card.en

        return VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {

                    // 1. Translation — large
                    Text(backLargeText)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.4)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    // 2. EN word + 🔊 audio
                    HStack(spacing: 6) {
                        Text(backSmallText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !card.dictAudioURL.isEmpty {
                            Button {
                                if audioService.isPlaying { audioService.stop() }
                                else { audioService.play(urlString: card.dictAudioURL) }
                            } label: {
                                Image(systemName: audioService.isPlaying
                                      ? "stop.circle.fill" : "speaker.wave.2.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    // 3. Examples — paged with slide transition
                    if !card.sampleEN.isEmpty {
                        let page = examplePageIndex
                        Divider().padding(.horizontal, 20)

                        VStack(spacing: 5) {
                            Text(card.sampleEN[page])
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            if page < card.sampleItem.count {
                                Text(card.sampleItem[page])
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .leading).combined(with: .opacity)
                        ))
                        .animation(.spring(duration: 0.3), value: page)

                        if card.sampleEN.count > 1 {
                            HStack(spacing: 7) {
                                ForEach(card.sampleEN.indices, id: \.self) { i in
                                    Circle()
                                        .strokeBorder(
                                            i == page ? Color.accentColor : Color(.systemGray3),
                                            lineWidth: 1.5
                                        )
                                        .frame(width: 7, height: 7)
                                        .onTapGesture {
                                            withAnimation(.spring(duration: 0.3)) {
                                                examplePageIndex = i
                                            }
                                        }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    // 4. Synonyms chips
                    if !card.synonyms.isEmpty {
                        Divider().padding(.horizontal, 20)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Synonyms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            CardFlowLayout(spacing: 6) {
                                ForEach(card.synonyms, id: \.self) { syn in
                                    Text(syn)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.secondary.opacity(0.12),
                                                    in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 8)
                }
            }
            .frame(maxHeight: .infinity)

            // Dictionary lookup — pinned to bottom, EN→Native only
            if !isReversed {
                Divider()
                Button { lookupCard = card } label: {
                    Label("Look up in dictionary", systemImage: "book.pages")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Background Cards

    private var cardPlaceholder: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(.systemBackground))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nextCardPreview(_ card: Card) -> some View {
        let frontText = isReversed ? card.item : card.en
        return ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
            Text(frontText)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Swipe Colour Overlay

    private var swipeColorOverlay: some View {
        let color: Color
        let opacity: Double
        if upSwipeProgress > 0 {
            color = .red; opacity = upSwipeProgress * 0.4
        } else {
            let p = viewModel.swipeProgress
            color = p > 0 ? .green : .blue; opacity = abs(p) * 0.45
        }
        return RoundedRectangle(cornerRadius: 24)
            .fill(color.opacity(opacity))
            .allowsHitTesting(false)
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard !viewModel.isFlipped else { return }
                viewModel.dragOffset = value.translation
            }
            .onEnded { value in
                guard !viewModel.isFlipped else { return }
                let dx = value.translation.width
                let dy = value.translation.height

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
                } else if dy < -upSwipeThreshold && abs(dx) < 55 {
                    withAnimation(.spring(duration: 0.4)) {
                        viewModel.dragOffset = CGSize(width: 0, height: -800)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.commitDelete(context: context)
                    }
                } else {
                    withAnimation(.spring(duration: 0.4, bounce: 0.4)) {
                        viewModel.dragOffset = .zero
                    }
                }
            }
    }

    // MARK: - SRS Buttons

    /// Portrait — horizontal row.
    private var srsButtonsRow: some View {
        HStack(spacing: 8) {
            srsButton(title: "Forgot", color: .indigo, rating: .again)
            srsButton(title: "Hard",   color: .orange, rating: .hard)
            srsButton(title: "Easy",   color: .green,  rating: .easy)
        }
    }

    /// Landscape — vertical column, buttons evenly distributed top-to-bottom.
    private var srsButtonsColumn: some View {
        VStack(spacing: 0) {
            Spacer()
            srsButton(title: "Forgot", color: .indigo, rating: .again)
            Spacer()
            srsButton(title: "Hard",   color: .orange, rating: .hard)
            Spacer()
            srsButton(title: "Easy",   color: .green,  rating: .easy)
            Spacer()
        }
        .padding(10)
    }

    @ViewBuilder
    private func srsButton(title: String, color: Color, rating: SRSRating) -> some View {
        Button { viewModel.evaluate(rating: rating, context: context) } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.35), lineWidth: 1))
        }
    }

    // MARK: - Done State

    private var doneFullCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(Color(.systemBackground))
            VStack(spacing: 0) {
                doneContentView
                doneActionsView
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

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
                    Text("\(viewModel.dueTomorrowCount)").font(.title2.bold())
                    Text("due tomorrow").font(.caption).foregroundStyle(.secondary)
                }
                Divider().frame(height: 36)
                VStack(spacing: 3) {
                    Text("\(viewModel.dueIn3DaysCount)").font(.title2.bold())
                    Text("due in 3 days").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private var doneActionsView: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) { viewModel.restart() }
            } label: {
                Text("Study again")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if viewModel.weakCount > 0 {
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.2)) { viewModel.restartWeak() }
                } label: {
                    Text("Weak cards: \(viewModel.weakCount)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.orange.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - CardFlowLayout

private struct CardFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}


// MARK: - Preview

#Preview {
    let config    = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Card.self, configurations: config)
    let ctx       = container.mainContext
    let setId     = UUID()
    let c1 = Card(en: "Serendipity", item: "счастливая случайность",
                  sampleEN:   ["What a serendipity to meet you here."],
                  sampleItem: ["Какая счастливая случайность встретить тебя здесь."],
                  synonyms: ["luck", "chance", "fortune"],
                  setId: setId)
    let c2 = Card(en: "Ephemeral",  item: "мимолётный", setId: setId)
    let c3 = Card(en: "Melancholy", item: "меланхолия", setId: setId)
    [c1, c2, c3].forEach { ctx.insert($0) }
    return TinderCardsView(cards: [c1, c2, c3],
                           contextLabels: [setId: "IELTS Vocabulary · Academic Words"],
                           pileTagsLine:  "IELTS Vocabulary › Academic Words (8 cards)")
        .modelContainer(container)
        .environment(AppViewModel())
}
