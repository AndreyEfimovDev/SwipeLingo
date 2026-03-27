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

    private func buildTranslationConfig() {
        #if !targetEnvironment(simulator)
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: DictionaryLookupViewModel.targetLangId(for: nativeLanguage))
        )
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
        return userSets.first(where: { $0.id == id })?.name ?? "Choose…"
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
                    setPickerSection               // visible in both add and edit modes
                    examplesENSection
                    examplesItemSection
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
                focused = .en
                if !isEditMode && userSets.isEmpty {
                    isCreatingNewSet = true
                }
                buildTranslationConfig()
            }
            .translationTask(translationConfig) { session in
                translationSession = session
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: handleSave) {
                Image(systemName: "checkmark")
                    .fontWeight(canSave ? .semibold : .regular)
                    .foregroundStyle(canSave ? Color.myColors.myBlue : Color.myColors.mySecondary)
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
        ToolbarItem(placement: .topBarTrailing) {
            if !en.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    Task { await handleAutoFill() }
                } label: {
                    if isAutoFilling {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.myColors.myBlue)
                    }
                }
                .disabled(isAutoFilling || isShowingExitConfirm)
            }
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
                print("[AutoFill] ⚠️ word translation failed: \(error)")
            }
        }

        // Step 2: fetch dictionary examples → fill samplesEN if empty
        let isSamplesEmpty = samplesEN.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard isSamplesEmpty else { return }

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
            guard !examples.isEmpty else { return }
            samplesEN = examples

            // Step 3: translate examples → fill samplesItem
            guard let session = translationSession else {
                samplesItem = Array(repeating: "", count: examples.count)
                return
            }
            do {
                let requests = examples.enumerated().map {
                    TranslationSession.Request(sourceText: $1, clientIdentifier: "\($0)")
                }
                let responses = try await session.translations(from: requests)
                var translated = Array(repeating: "", count: examples.count)
                for response in responses {
                    if let id = response.clientIdentifier, let idx = Int(id) {
                        translated[idx] = response.targetText
                    }
                }
                samplesItem = translated
            } catch {
                samplesItem = Array(repeating: "", count: examples.count)
                print("[AutoFill] ⚠️ examples translation failed: \(error)")
            }
        } catch {
            print("[AutoFill] ⚠️ dictionary lookup failed: \(error)")
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
            }
        } label: {
            HStack {
                Text(selectedSetName)
                    .font(.body)
                    .foregroundStyle(selectedSetId == nil
                        ? Color.myColors.mySecondary
                        : Color.myColors.myAccent)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.myColors.mySecondary)
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
                        Text("Choose existing set")
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
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.myColors.myRed.opacity(0.5))
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
                .foregroundStyle(Color.myColors.mySecondary)
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
                    .font(.headline)
                    .foregroundStyle(Color.myColors.myAccent)

                Button { dismiss() } label: {
                    Text("Discard")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.myColors.myRed)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    withAnimation(.easeInOut) { isShowingExitConfirm = false }
                    focused = .en
                } label: {
                    Text("Keep editing")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.myAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.myColors.mySecondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 40)
        }
    }
}
