import SwiftUI
import SwiftData

// MARK: - TinderCardsView

struct TinderCardsView: View {

    @Environment(\.modelContext)       private var context
    @Environment(\.verticalSizeClass)  private var verticalSizeClass
    @Environment(AppViewModel.self)    private var appViewModel
    
    @AppStorage("ttsVoiceIdentifier")   private var ttsVoiceIdentifier  = ""
    @AppStorage("englishVariant")       private var englishVariant      = "en-US"
    @AppStorage("srsEnabled")           private var srsEnabled: Bool    = true

    @State private var viewModel: TinderCardsViewModel
    @State private var lookupCard: Card?
    @State private var audioService  = AudioPlayerService()
    @State private var examplePageIndex: Int = 0
    /// Automatically resets to false when DragGesture ends OR is cancelled (e.g. second finger).
    @GestureState private var dragIsActive = false

    private let swipeThreshold:   CGFloat = 110
    private let upSwipeThreshold: CGFloat = 100
    private let pileTagsLine: String
    private let cefrLabels: [UUID: CEFRLevel]
    /// True when study session shows only due cards — changes "Active" label to "Due".
    private let isDueMode: Bool
    /// Cards already in .learnt status in the pile at session start (added to learntInSession).
    private let pileLearntCount: Int
    /// Called when the user taps the mode toggle in the progress row.
    private let onToggleMode: (() -> Void)?

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
         cefrLabels: [UUID: CEFRLevel] = [:],
         pileTagsLine: String = "",
         isDueMode: Bool = false,
         pileLearntCount: Int = 0,
         onToggleMode: (() -> Void)? = nil,
         onDone: (() -> Void)? = nil) {
        _viewModel             = State(initialValue: TinderCardsViewModel(
                                    cards: cards,
                                    contextLabels: contextLabels,
                                    onDone: onDone))
        self.cefrLabels        = cefrLabels
        self.pileTagsLine      = pileTagsLine
        self.isDueMode         = isDueMode
        self.pileLearntCount   = pileLearntCount
        self.onToggleMode      = onToggleMode
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLandscape { landscapeBody } else { portraitBody }
        }
        .background(Color.myColors.myBackground)
        .animation(.spring(duration: 0.3), value: viewModel.currentIndex)
        .animation(.spring(duration: 0.3), value: viewModel.isFlipped)
        .animation(.spring(duration: 0.4), value: viewModel.isDone)
        .sheet(item: $lookupCard) { DictionaryLookupView(card: $0) }
        .onDisappear { audioService.stop() }
        .onChange(of: viewModel.currentIndex) { _, _ in
            examplePageIndex = 0
            audioService.stop()
        }
    }

    // MARK: - Portrait

    private var portraitBody: some View {
        VStack(spacing: 0) {
            if !viewModel.isDone {
                progressStatsRow
                    .padding(.bottom, 8)
            }

            ZStack {
                if viewModel.isDone { doneFullCard } else { cardStack }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    // MARK: - Landscape

    private var landscapeBody: some View {
        HStack(spacing: 0) {
            landscapeStatsColumn
            ZStack {
                if viewModel.isDone { doneFullCard } else { cardStack }
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 16)

    }

    // MARK: - Landscape Stats Column

    private var landscapeStatsColumn: some View {
        let allCards    = viewModel.cards
        let effTotal    = allCards.filter { $0.status != .deleted }.count
        let learnt      = pileLearntCount + viewModel.learntInSession
        let active      = allCards.filter { $0.status == .active }.count
        let deletedSoFar = allCards.prefix(viewModel.currentIndex).filter { $0.status == .deleted }.count
        let current     = min(viewModel.currentIndex - deletedSoFar + 1, max(effTotal, 1))
        let progress    = effTotal > 0 ? CGFloat(max(0, viewModel.currentIndex - deletedSoFar)) / CGFloat(effTotal) : 0

        return HStack(spacing: 0) {
            // Stats content
            VStack(spacing: 0) {
                Spacer()
                statLabel("Learnt", value: learnt, status: .learnt)
                Spacer()
                modeCenterButton(current: current, effTotal: effTotal)
                    .font(.caption2)
                Spacer()
                statLabel(isDueMode ? "Due" : "Active", value: active, status: .active)
                Spacer()
            }
            .frame(maxWidth: .infinity)

            // Vertical progress bar — right edge, replaces Divider with meaning
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.myColors.myAccent.opacity(0.15))
                        .frame(width: 3, height: geo.size.height)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.myColors.myAccent.opacity(0.5))
                        .frame(width: 3, height: geo.size.height * progress)
                        .animation(.spring(duration: 0.4), value: progress)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: 8)
        }
        .frame(maxWidth: 64)
    }

    /// Centre of the progress row: "1 / 14" when no toggle, or "Due · 1/14 ⇅" when tappable.
    @ViewBuilder
    private func modeCenterButton(current: Int, effTotal: Int) -> some View {
        if let toggle = onToggleMode {
            Button(action: toggle) {
                HStack(spacing: 3) {
                    Text(isDueMode ? "Due" : "All")
                        .foregroundStyle(isDueMode ? Color.myColors.myOrange : Color.myColors.myGreen)
                    Text("·")
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                    Text("\(current) / \(effTotal)")
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.45))
                }
            }
            .buttonStyle(.plain)
        } else {
            Text("\(current) / \(effTotal)")
                .fontWeight(.semibold)
        }
    }

    private func statLabel(_ title: String, value: Int, status: CardStatus) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9))
            Text("\(value)")
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(status.color)
        }
    }

    // MARK: - Portrait Stats Row

    private var progressStatsRow: some View {
        let allCards = viewModel.cards
        let effTotal = allCards.filter { $0.status != .deleted }.count
        let learnt   = pileLearntCount + viewModel.learntInSession
        let active   = allCards.filter { $0.status == .active }.count
        let deletedSoFar = allCards.prefix(viewModel.currentIndex).filter { $0.status == .deleted }.count
        let current  = min(viewModel.currentIndex - deletedSoFar + 1, max(effTotal, 1))
        let progress = effTotal > 0 ? CGFloat(max(0, viewModel.currentIndex - deletedSoFar)) / CGFloat(effTotal) : 0

        return VStack(spacing: 6) {
            HStack {
                Text("\(active)")
                    .bold()
                    .foregroundStyle(CardStatus.active.color)
                VStack(spacing: 4){
                    HStack {
                        Text(isDueMode ? "Due" : "Active")
                        Spacer()
                        modeCenterButton(current: current, effTotal: effTotal)
                        Spacer()
                        Text("Learnt")
                    }.font(.caption2)
                    
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.myColors.myAccent.opacity(0.1))
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.myColors.myAccent.opacity(0.5))
                                .frame(width: geo.size.width * progress, height: 3)
                                .animation(.spring(duration: 0.4), value: progress)
                        }
                    }
                    .frame(height: 3)
                }
                Text("\(learnt)")
                    .bold()
                    .foregroundStyle(CardStatus.learnt.color)
            }
            .font(.title3)
        }
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
            HStack(spacing: 6) {
                Text(label)
                CEFRBadgeView(level: viewModel.currentCard.flatMap { cefrLabels[$0.setId] })
            }
            .font(.caption2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        ZStack {
            let dragProgress = min(1.0, abs(viewModel.dragOffset.width) / swipeThreshold)

            ForEach([2, 1], id: \.self) { offset in
                let idx = viewModel.currentIndex + offset
                if idx < viewModel.cards.count {
                    let step:        CGFloat = isLandscape ? 0.05 : 0.06
                    let yStep:       CGFloat = isLandscape ? -20.0 : -28.0
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
                    .myShadow()
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
            .onTapGesture {
                // Block tap while drag is active OR while card is spring-animating back.
                guard !dragIsActive, !viewModel.isDragging else { return }
                viewModel.flipToggle()
            }
            .onChange(of: dragIsActive) { _, isActive in
                guard !isActive else { return }
                // Drag ended or was cancelled (e.g. second finger tap).
                // onEnded sets dragOffset to ±600 / -800 only when a swipe is fully
                // committed. Any smaller value means the gesture was cancelled mid-drag
                // and the card must return to centre regardless of swipeThreshold.
                let isFlying = abs(viewModel.dragOffset.width) > 400
                            || viewModel.dragOffset.height < -400

                if !isFlying {
                    withAnimation(.spring(duration: 0.4, bounce: 0.4)) {
                        viewModel.dragOffset = .zero
                    }
                }
                // Clear isDragging after spring settles (covers both normal & cancel paths)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    viewModel.isDragging = false
                }
            }
            .myShadow()
    }

    // MARK: - Full Card Container

    private func fullCardContainer(_ card: Card) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.myColors.myBackground)
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
            // SRS pinned to bottom — hidden when SRS is disabled in Settings
            if srsEnabled {
                srsButtonsRow
                    .padding(12)
                    .opacity(viewModel.isFlipped ? 1 : 0)
                    .allowsHitTesting(viewModel.isFlipped)
                    .animation(.spring(duration: 0.35, bounce: 0.2), value: viewModel.isFlipped)
            }
        }
    }

    private func landscapeCardContent(_ card: Card) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                breadcrumbRow
                flipContent(card: card).frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)

            // SRS column — only present on back side, no reserved space on front
            if srsEnabled && viewModel.isFlipped {
                srsButtonsColumn
                    .frame(width: 90)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isFlipped)
    }

    // MARK: - Flip Content

    private func flipContent(card: Card) -> some View {
        ZStack {
            cardFront(card)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rotation3DEffect(.degrees(viewModel.isFlipped ? 180 : 0),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .opacity(viewModel.isFlipped ? 0 : 1)
                .allowsHitTesting(!viewModel.isFlipped)

            cardBack(card)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rotation3DEffect(.degrees(viewModel.isFlipped ? 0 : -180),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .opacity(viewModel.isFlipped ? 1 : 0)
                .allowsHitTesting(viewModel.isFlipped)
        }
        .animation(.spring(duration: 0.5, bounce: 0.15), value: viewModel.isFlipped)
    }

    // MARK: - Audio Button

    /// Reusable audio button: myBlue when idle, myRed when this specific audio is playing.
    /// - Parameters:
    ///   - text:  URL string for network audio, or plain text for TTS.
    ///   - isTTS: `true` → uses AVSpeechSynthesizer; `false` → uses AVPlayer.
    @ViewBuilder
    private func audioButton(for text: String, isTTS: Bool = false) -> some View {
        let key = isTTS ? "tts:\(text)" : text
        let isThisPlaying = audioService.isPlaying && audioService.currentURL == key
        Button {
            if isThisPlaying {
                audioService.stop()
            } else if isTTS {
                audioService.speak(text: text, voiceIdentifier: ttsVoiceIdentifier, language: englishVariant)
            } else {
                audioService.play(urlString: text)
            }
        } label: {
            Image(systemName: isThisPlaying ? "stop.circle" : "speaker.wave.2.circle")
                .foregroundStyle(isThisPlaying ? Color.myColors.myRed : Color.myColors.myBlue)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Card Front

    private func cardFront(_ card: Card) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(card.en)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)
            audioButton(for: card.en, isTTS: true)
                .font(.largeTitle)
            Spacer()
            Text("Tap to check")
                .font(.caption2)
                .padding(.bottom, 20)
                .opacity(0.75)
        }
    }

    // MARK: - Card Back

    private func cardBack(_ card: Card) -> some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 14) {

                    // 1. Translation — large
                    Text(card.item)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.4)
                        .padding(.horizontal, 20)

                    // 2. EN word + 🔊 audio
                    HStack(spacing: 6) {
                        Text(card.en)
                            .font(.subheadline)
                        audioButton(for: card.en, isTTS: true)
                            .font(.subheadline)
                    }

                    // 3. Examples — paged with arrow navigation
                    if !card.sampleEN.isEmpty {
                        let count = card.sampleEN.count
                        let page = min(examplePageIndex, count - 1)
                        let hasMany = count > 1
                        Divider().padding(.horizontal, 20)

                        HStack(spacing: 0) {
                            // Left arrow — invisible on first page, keeps space always
                            Button {
                                withAnimation(.spring(duration: 0.3)) {
                                    examplePageIndex -= 1
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.myColors.myBlue)
                                    .frame(width: 36, height: 36)
                            }
                            .opacity(hasMany && page > 0 ? 1 : 0)
                            .disabled(!hasMany || page == 0)

                            // Example content
                            VStack(spacing: 5) {
                                Text(card.sampleEN[page])
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                audioButton(for: card.sampleEN[page], isTTS: true)
                                if page < card.sampleItem.count {
                                    Text(card.sampleItem[page])
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .font(.subheadline)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .id(page)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal:   .move(edge: .leading).combined(with: .opacity)
                            ))
                            .animation(.spring(duration: 0.3), value: page)

                            // Right arrow — invisible on last page, keeps space always
                            Button {
                                withAnimation(.spring(duration: 0.3)) {
                                    examplePageIndex += 1
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.myColors.myBlue)
                                    .frame(width: 36, height: 36)
                            }
                            .opacity(hasMany && page < count - 1 ? 1 : 0)
                            .disabled(!hasMany || page == count - 1)
                        }
                        .padding(.horizontal, 4)
                    }

                    // 4. Synonyms chips
                    if !card.synonyms.isEmpty {
                        Divider().padding(.horizontal, 20)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Synonyms")
                                .font(.caption)
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
            
            // Tap to back hint — back side
            Text("Tap to back")
                .font(.caption2)
                .opacity(0.75)

            // Dictionary lookup
            Button { lookupCard = card } label: {
                Label("Look up in dictionary", systemImage: "book.pages")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myBlue)
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Background Cards

    private var cardPlaceholder: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color.myColors.myBackground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nextCardPreview(_ card: Card) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.myColors.myBackground)
            VStack(spacing: 12) {
                Spacer()
                Text(card.en)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 24)
                audioButton(for: card.en, isTTS: true)
                    .font(.largeTitle)
                Spacer()
                Text("Tap to check")
                    .font(.caption2)
                    .padding(.bottom, 20)
                    .opacity(0.75)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Swipe Colour Overlay

    private var swipeColorOverlay: some View {
        let color: Color
        let opacity: Double
        if upSwipeProgress > 0 {
            // Swipe up = delete
            color = CardStatus.deleted.color; opacity = upSwipeProgress * 0.4
        } else {
            let p = viewModel.swipeProgress
            // Swipe right = learnt (green), swipe left = active/again (blue)
            color = p > 0 ? CardStatus.learnt.color : CardStatus.active.color
            opacity = abs(p) * 0.45
        }
        return RoundedRectangle(cornerRadius: 24)
            .fill(color.opacity(opacity))
            .allowsHitTesting(false)
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            // updating fires on every change AND resets automatically on end OR cancel
            .updating($dragIsActive) { _, state, _ in state = true }
            .onChanged { value in
                guard !viewModel.isFlipped else { return }
                viewModel.isDragging = true
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
                }
                // Return-to-centre is handled by onChange(of: dragIsActive) below —
                // this covers both normal release AND gesture cancellation (second finger).
            }
    }

    // MARK: - SRS Buttons

    /// Portrait — horizontal row.
    private var srsButtonsRow: some View {
        HStack(spacing: 8) {
            srsButton(title: "Forgot", color: Color.myColors.myPurple, rating: .again)
            srsButton(title: "Hard",   color: Color.myColors.myOrange, rating: .hard)
            srsButton(title: "Easy",   color: Color.myColors.myGreen,  rating: .easy)
        }
    }

    /// Landscape — vertical column, buttons evenly distributed top-to-bottom.
    private var srsButtonsColumn: some View {
        VStack(spacing: 0) {
            Spacer()
            srsButton(title: "Forgot", color: Color.myColors.myPurple, rating: .again)
            Spacer()
            srsButton(title: "Hard",   color: Color.myColors.myOrange, rating: .hard)
            Spacer()
            srsButton(title: "Easy",   color: Color.myColors.myGreen,  rating: .easy)
            Spacer()
        }
        .padding(10)
    }

    @ViewBuilder
    private func srsButton(title: String, color: Color, rating: SRSRating) -> some View {
        Button { viewModel.evaluate(rating: rating, context: context) } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.85), lineWidth: 1))
        }
    }

    // MARK: - Done State

    private var doneFullCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(Color.myColors.myBackground)
            VStack(spacing: 0) {
                doneContentView
                doneActionsView
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .myShadow()
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
                    Text("due tomorrow").font(.caption)
                }
                Divider().frame(height: 36)
                VStack(spacing: 3) {
                    Text("\(viewModel.dueIn3DaysCount)").font(.title2.bold())
                    Text("due in 3 days").font(.caption)
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
