import SwiftUI
import SwiftData
import Translation

// MARK: - AddEditCardView
// Unified add / edit sheet for a Card.
//
// Add mode  (card == nil):
//   • preselectedSetId — optional, pre-fills the set picker
//   • userSets empty   — inline "create set" field; set is created on save inside My Sets
//   • userSets present — Menu picker; "New set…" option at the bottom
//
// Edit mode (card != nil):
//   • Working copy compared to original snapshot
//   • checkmark active only when changes exist
//   • xmark shows confirmation only when changes exist
//   • SET section available — card can be moved to another set

struct AddEditCardView: View {

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \CardSet.createdAt)    private var allSets: [CardSet]
    @Query(sort: \Collection.createdAt) private var allCollections: [Collection]

    // MARK: - Mode & snapshot
    private let originalCard:  Card?
    private let originalSetId: UUID?       // captured at init for change detection
    private let preselectedSetId: UUID?

    // MARK: - Working copy
    @State private var en:          String
    @State private var item:        String
    @State private var samplesEN:   [String]
    @State private var samplesItem: [String]

    // Set picker
    @State private var selectedSetId:    UUID?
    @State private var isCreatingNewSet: Bool   = false
    @State private var newSetName:       String = ""

    @State private var isShowingExitConfirm = false
    @FocusState private var focused: Field?

    // Auto-fill (dictionary + Apple Translation)
    @AppStorage("nativeLanguage") private var nativeLanguage = "Русский"
    @State private var translationSession: TranslationSession?
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var isAutoFilling = false
    @State private var autoFillTask: Task<Void, Never>?

    // Keyboard
    @State private var keyboard = KeyboardManager()

    enum Field: Hashable {
        case en, item, newSetName
        case sampleEN(Int), sampleItem(Int)
    }

    // MARK: - Init

    init(card: Card? = nil, preselectedSetId: UUID? = nil) {
        originalCard        = card
        originalSetId       = card?.setId
        self.preselectedSetId = preselectedSetId

        _en          = State(initialValue: card?.en   ?? "")
        _item        = State(initialValue: card?.item ?? "")
        _samplesEN   = State(initialValue: card.flatMap { $0.sampleEN.isEmpty   ? nil : $0.sampleEN }   ?? [""])
        _samplesItem = State(initialValue: card.flatMap { $0.sampleItem.isEmpty ? nil : $0.sampleItem } ?? [""])
        _selectedSetId = State(initialValue: card?.setId ?? preselectedSetId)
    }

    // MARK: - Computed

    private var isEditMode: Bool { originalCard != nil }

    // Кнопка видна пока есть хотя бы одно незаполненное поле
    private var hasEmptyAutoFillFields: Bool {
        item.trimmingCharacters(in: .whitespaces).isEmpty
        || samplesEN.allSatisfy  { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        || samplesItem.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func buildTranslationConfig() {
        #if !targetEnvironment(simulator)
        let langId = DictionaryLookupViewModel.targetLangId(for: nativeLanguage)
        log("buildTranslationConfig: nativeLanguage=\(nativeLanguage) → langId=\(langId)", level: .info)
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: langId)
        )
        #else
        log("buildTranslationConfig: skipped on simulator", level: .warning)
        #endif
    }

    /// User-created sets, excluding Inbox.
    /// Double-filtered by CardSet.isUserCreated AND parent Collection.isUserCreated
    /// to handle legacy migration defaults.
    private var userSets: [CardSet] {
        let userCollectionIds = Set(allCollections.filter { $0.isUserCreated }.map { $0.id })
        return allSets.filter {
            $0.isUserCreated &&
            userCollectionIds.contains($0.collectionId) &&
            $0.name != "Inbox"
        }
    }

    private var selectedSetName: String {
        guard let id = selectedSetId else { return "Choose or add a new set…" }
        return userSets.first(where: { $0.id == id })?.name ?? "Choose a set"
    }

    private var hasChanges: Bool {
        let enTrim   = en.trimmingCharacters(in: .whitespaces)
        let itemTrim = item.trimmingCharacters(in: .whitespaces)
        let snEN   = samplesEN.map   { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let snItem = samplesItem.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        guard let original = originalCard else {
            // Add mode — any filled field counts as a change
            return !enTrim.isEmpty || !itemTrim.isEmpty ||
                   !newSetName.isEmpty || selectedSetId != nil ||
                   snEN.contains(where: { !$0.isEmpty }) ||
                   snItem.contains(where: { !$0.isEmpty })
        }
        // Edit mode — compare working copy with original snapshot
        return enTrim != original.en    ||
               itemTrim != original.item ||
               snEN != original.sampleEN ||
               snItem != original.sampleItem ||
               selectedSetId != originalSetId
    }

    private var canSave: Bool {
        let enOK = !en.trimmingCharacters(in: .whitespaces).isEmpty
        if isEditMode {
            return enOK && hasChanges          // active only when something changed
        }
        if isCreatingNewSet {
            return enOK && !newSetName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return enOK && selectedSetId != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    enSection
                    itemSection
                    setPickerSection
                    examplesENSection
                    examplesItemSection
                    autoFillButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle(isEditMode ? "Edit Card" : "New Card")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar { toolbarContent }
            .overlay { if isShowingExitConfirm { exitConfirmOverlay } }
            .onAppear {
                focused = nil // prevent popup keyboard when started
                if !isEditMode && userSets.isEmpty {
                    isCreatingNewSet = true
                }
                buildTranslationConfig()
            }
            .onDisappear {
                autoFillTask?.cancel()
            }
            .translationTask(translationConfig) { session in
                log("translationTask: session received ✓", level: .info)
                translationSession = session
            }
            .overlay(alignment: .bottomTrailing) {
                hideKeyboardButton
            }
        }
    }

    // MARK: - Hide Keyboard Button

    @ViewBuilder
    private var hideKeyboardButton: some View {
        if focused != nil && keyboard.shouldShowHideButton {
            Button {
                focused = nil
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.title2)
                    .foregroundStyle(Color.myColors.myBlue)
                    .frame(width: 48, height: 48)
                    .background(Color.myColors.myBackground)
                    .clipShape(Circle())
                    .myShadow()
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: handleSave) {
                Image(systemName: "checkmark")
                    .fontWeight(canSave ? .semibold : .regular)
                    .foregroundStyle(canSave ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.8))
            }
            .disabled(!canSave || isShowingExitConfirm)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: handleCancel) {
                Image(systemName: "xmark")
                    .foregroundStyle(Color.myColors.myRed)
                    .fontWeight(.semibold)
            }
            .disabled(isShowingExitConfirm)
        }
    }

    // MARK: - Actions

    private func handleSave() {
        let enClean   = en.trimmingCharacters(in: .whitespaces)
        let itemClean = item.trimmingCharacters(in: .whitespaces)
        let snEN   = samplesEN.map   { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let snItem = samplesItem.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if let original = originalCard {
            original.en         = enClean
            original.item       = itemClean
            original.sampleEN   = snEN
            original.sampleItem = snItem
            if let newSetId = resolveSetId() { original.setId = newSetId }
        } else {
            guard let setId = resolveSetId() else { return }
            let card = Card(en: enClean, item: itemClean,
                            sampleEN: snEN, sampleItem: snItem, setId: setId)
            context.insert(card)
        }
        try? context.save()
        dismiss()
    }

    /// Returns target setId; creates a new CardSet if isCreatingNewSet.
    private func resolveSetId() -> UUID? {
        if isCreatingNewSet {
            let setName = newSetName.trimmingCharacters(in: .whitespaces)
            guard !setName.isEmpty else { return nil }
            let collection = allCollections.first(where: { $0.name == "My Sets" })
                          ?? allCollections.first(where: { $0.isUserCreated })
            guard let collection else { return nil }
            let newSet = CardSet(name: setName, collectionId: collection.id, isUserCreated: true)
            context.insert(newSet)
            return newSet.id
        }
        return selectedSetId
    }

    /// Fetches dictionary examples and Apple translations; fills empty fields only.
    private func handleAutoFill() async {
        let word = en.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        focused = nil          // dismiss keyboard before filling
        isAutoFilling = true
        defer { isAutoFilling = false }

        log("handleAutoFill: word='\(word)', session=\(translationSession == nil ? "nil ❌" : "ready ✓")", level: .info)

        // Step 1: translate the word itself → fill item if empty
        if item.trimmingCharacters(in: .whitespaces).isEmpty,
           let session = translationSession {
            do {
                let req = TranslationSession.Request(sourceText: word, clientIdentifier: "word")
                let responses = try await session.translations(from: [req])
                if let translated = responses.first?.targetText {
                    item = translated
                }
            } catch {
                log("word translation failed: \(error)", level: .warning)
            }
        }

        guard !Task.isCancelled else { return }

        // Step 2: fetch EN examples from dictionary if empty
        let isENEmpty = samplesEN.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        if isENEmpty {
            do {
                let entry = try await DictionaryService().lookup(word: word)
                // Prefer example sentences; fall back to definition text if none available.
                var examples: [String] = []
                for meaning in entry.meanings {
                    for def in meaning.definitions {
                        let text = def.example ?? def.text
                        if !examples.contains(text) {
                            examples.append(text)
                            if examples.count >= 3 { break }
                        }
                    }
                    if examples.count >= 3 { break }
                }
                if !examples.isEmpty { samplesEN = examples }
            } catch {
                log("dictionary lookup failed: \(error)", level: .warning)
            }
        }

        guard !Task.isCancelled else { return }

        // Step 3: translate EN examples → fill native examples if empty
        // Runs whether EN examples were just fetched or already existed
        let isNativeEmpty = samplesItem.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        let enExamples = samplesEN.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard isNativeEmpty, !enExamples.isEmpty, let session = translationSession else { return }

        do {
            let requests = enExamples.enumerated().map {
                TranslationSession.Request(sourceText: $1, clientIdentifier: "\($0)")
            }
            let responses = try await session.translations(from: requests)
            var translated = Array(repeating: "", count: enExamples.count)
            for response in responses {
                if let id = response.clientIdentifier, let idx = Int(id) {
                    translated[idx] = response.targetText
                }
            }
            samplesItem = translated
        } catch {
            samplesItem = Array(repeating: "", count: enExamples.count)
            log("examples translation failed: \(error)", level: .warning)
        }
    }

    private func handleCancel() {
        if hasChanges {
            focused = nil
            withAnimation(.easeInOut) { isShowingExitConfirm = true }
        } else {
            dismiss()
        }
    }

    // MARK: - Field Sections

    private var enSection: some View {
        fieldSection(label: "ENGLISH") {
            HStack(spacing: 8) {
                TextField("Word or phrase", text: $en, axis: .vertical)
                    .font(.body)
                    .focused($focused, equals: .en)
                    .submitLabel(.next)
                    .onSubmit { focused = .item }
                if !en.isEmpty {
                    clearButton { en = "" }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var itemSection: some View {
        fieldSection(label: "TRANSLATION") {
            HStack(spacing: 8) {
                TextField("Native translation", text: $item, axis: .vertical)
                    .font(.body)
                    .focused($focused, equals: .item)
                    .submitLabel(.next)
                    .onSubmit { focused = .sampleEN(0) }
                if !item.isEmpty {
                    clearButton { item = "" }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Set Picker Section

    private var setPickerSection: some View {
        fieldSection(label: "SET") {
            if isCreatingNewSet {
                newSetField
            } else {
                existingSetMenu
            }
        }
    }

    /// Menu with existing user sets + "New set…" at the bottom
    private var existingSetMenu: some View {
        Menu {
            ForEach(userSets) { set in
                Button {
                    selectedSetId = set.id
                } label: {
                    HStack {
                        Text(set.name)
                        if selectedSetId == set.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                selectedSetId = nil
                isCreatingNewSet = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    focused = .newSetName
                }
            } label: {
                Label("New set…", systemImage: "plus")
                    .foregroundStyle(Color.myColors.myBlue)
            }
        } label: {
            HStack {
                Text(selectedSetName)
                    .font(.body)
                    .foregroundStyle(selectedSetId == nil
                        ? Color.myColors.myAccent.opacity(0.8)
                        : Color.myColors.myAccent)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.myColors.myBlue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    /// Inline new-set name field
    @ViewBuilder
    private var newSetField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Set name", text: $newSetName)
                    .font(.body)
                    .focused($focused, equals: .newSetName)
                    .submitLabel(.next)
                    .onSubmit { focused = .sampleEN(0) }
                if !newSetName.isEmpty {
                    clearButton { newSetName = "" }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !userSets.isEmpty {
                Divider()
                Button {
                    newSetName = ""
                    isCreatingNewSet = false
                    selectedSetId = originalSetId ?? preselectedSetId
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                        Text("Choose a set")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Color.myColors.myBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Auto-fill Button

    @ViewBuilder
    private var autoFillButton: some View {
        if !en.trimmingCharacters(in: .whitespaces).isEmpty && (isAutoFilling || hasEmptyAutoFillFields) {
            Button {
                guard !isAutoFilling else { return }
                autoFillTask = Task { await handleAutoFill() }
            } label: {
                Group {
                    if isAutoFilling {
                        ProgressView()
                            .tint(Color.myColors.myBlue)
                            .frame(width: 20, height: 20)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("Auto-fill card")
                            .font(.headline)
                            .foregroundStyle(Color.myColors.myBlue)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, isAutoFilling ? 14 : 20)
                .padding(.vertical, 14)
                .overlay { Capsule().strokeBorder(Color.myColors.myBlue, lineWidth: 1.5) }
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: isAutoFilling)
        }
    }

    // MARK: - Example Sections

    private var examplesENSection: some View {
        fieldSection(label: "ENGLISH EXAMPLES") {
            examplesList(samples: $samplesEN, fieldTag: { .sampleEN($0) }, isLastSection: false)
        }
    }

    private var examplesItemSection: some View {
        fieldSection(label: "NATIVE EXAMPLES") {
            examplesList(samples: $samplesItem, fieldTag: { .sampleItem($0) }, isLastSection: true)
        }
    }

    private func examplesList(
        samples: Binding<[String]>,
        fieldTag: @escaping (Int) -> Field,
        isLastSection: Bool
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(samples.wrappedValue.indices, id: \.self) { i in
                let isLastField = i == samples.wrappedValue.count - 1
                HStack(spacing: 8) {
                    TextField("Example \(i + 1)", text: samples[i], axis: .vertical)
                        .font(.body)
                        .focused($focused, equals: fieldTag(i))
                        .submitLabel(isLastField ? .done : .next)
                        .onSubmit {
                            if !isLastField {
                                focused = fieldTag(i + 1)
                            } else if isLastSection {
                                focused = .en
                            }
                        }
                    if !samples.wrappedValue[i].isEmpty {
                        clearButton {
                            withAnimation(.spring(duration: 0.25)) {
                                if samples.wrappedValue.count > 1 {
                                    var updated = samples.wrappedValue
                                    updated.remove(at: i)
                                    samples.wrappedValue = updated
                                } else {
                                    samples.wrappedValue[i] = ""
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if i < samples.wrappedValue.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }

            Divider()

            Button {
                withAnimation(.spring(duration: 0.25)) { samples.wrappedValue.append("") }
                let newIndex = samples.wrappedValue.count - 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    focused = fieldTag(newIndex)
                }
            } label: {
                Label("Add example", systemImage: "plus")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Clear Button

    private func clearButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle")
                .foregroundStyle(Color.myColors.myRed.opacity(0.8))
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Section Wrapper

    private func fieldSection<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .padding(.horizontal, 16)

            content()
                .background(Color.myColors.myBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .myShadow()
        }
    }

    // MARK: - Exit Confirmation

    private var exitConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut) { isShowingExitConfirm = false }
                    focused = .en
                }

            VStack(spacing: 10) {
                Text("Discard changes?")
                    .font(.subheadline)

                Button { dismiss() } label: {
                    Text("Discard")
                        .buttonRect(color: Color.myColors.myRed)
                }

                Button {
                    withAnimation(.easeInOut) { isShowingExitConfirm = false }
                    focused = .en
                } label: {
                    Text("Keep editing")
                        .buttonRect(color: Color.myColors.myBlue)
                }
            }
            .font(.headline)
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 40)
        }
    }
}
