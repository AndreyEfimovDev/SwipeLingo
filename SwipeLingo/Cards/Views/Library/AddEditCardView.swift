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
//
// Вся бизнес-логика (working copy, валидация, auto-fill) живёт в AddEditCardViewModel.
// Здесь остаётся разметка и то, что физически не может жить вне View: @Query, @FocusState,
// @AppStorage, навигационный @State (isShowingExitConfirm).

struct AddEditCardView: View {

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \CardSet.createdAt)    private var allSets: [CardSet]
    @Query(sort: \Collection.createdAt) private var allCollections: [Collection]
    @Query                              private var allCards: [Card]

    @State private var viewModel: AddEditCardViewModel

    @State private var isShowingExitConfirm = false
    @FocusState private var focused: Field?

    // Auto-fill (dictionary + Apple Translation)
    @AppStorage(Constants.StorageKey.nativeLanguage) private var nativeLanguage: NativeLanguage = .russian

    // Keyboard
    @State private var keyboard = KeyboardManager()

    enum Field: Hashable {
        case en, item, newSetName
        case sampleEN(Int), sampleItem(Int)
    }

    // MARK: - Init

    init(card: Card? = nil, preselectedSetId: UUID? = nil) {
        _viewModel = State(initialValue: AddEditCardViewModel(card: card, preselectedSetId: preselectedSetId))
    }

    // MARK: - Computed (делегируют в VM, добавляя @Query-результаты)

    private var userSets: [CardSet] {
        viewModel.userSets(allSets: allSets, allCollections: allCollections)
    }

    private var selectedSetName: String {
        viewModel.selectedSetName(allSets: allSets, allCollections: allCollections)
    }

    private var isDuplicateEN: Bool {
        viewModel.isDuplicateEN(allCards: allCards)
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
            .navigationTitle(viewModel.isEditMode ? "Edit Card" : "New Card")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar { toolbarContent }
            .overlay { if isShowingExitConfirm { exitConfirmOverlay } }
            .onAppear {
                focused = nil // prevent popup keyboard when started
                if !viewModel.isEditMode && userSets.isEmpty {
                    viewModel.isCreatingNewSet = true
                }
                viewModel.buildTranslationConfig(nativeLanguage: nativeLanguage)
            }
            .onDisappear {
                viewModel.cancelAutoFillTask()
            }
            .translationTask(viewModel.translationConfig) { session in
                log("translationTask: session received ✓", level: .info)
                viewModel.translationSession = session
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
                    .font(.subheadline.weight(viewModel.canSave ? .semibold : .regular))
                    .foregroundStyle(viewModel.canSave ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.8))
            }
            .disabled(!viewModel.canSave || isShowingExitConfirm)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: handleCancel) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.myColors.myRed)
            }
            .disabled(isShowingExitConfirm)
        }
    }

    // MARK: - Actions

    private func handleSave() {
        guard viewModel.handleSave(context: context, allCollections: allCollections) else { return }
        dismiss()
    }

    private func handleCancel() {
        if viewModel.hasChanges {
            focused = nil
            withAnimation(.easeInOut) { isShowingExitConfirm = true }
        } else {
            dismiss()
        }
    }

    // MARK: - Field Sections

    private var enSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldSection(label: "ENGLISH") {
                HStack(spacing: 8) {
                    TextField("Word or phrase", text: $viewModel.en, axis: .vertical)
                        .font(.body)
                        .focused($focused, equals: .en)
                        .submitLabel(.next)
                        .onSubmit { focused = .item }
                    if !viewModel.en.isEmpty {
                        clearButton { viewModel.en = "" }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            if isDuplicateEN {
                Label("Already exists in this set", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.myColors.myOrange)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }
            lengthHint(for: viewModel.en, state: viewModel.enLengthState)
        }
        .animation(.easeInOut(duration: 0.2), value: isDuplicateEN)
        .animation(.easeInOut(duration: 0.2), value: viewModel.enLengthState == .ok)
    }

    private var itemSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldSection(label: "TRANSLATION") {
                HStack(spacing: 8) {
                    TextField("Native translation", text: $viewModel.item, axis: .vertical)
                        .font(.body)
                        .focused($focused, equals: .item)
                        .submitLabel(.next)
                        .onSubmit { focused = .sampleEN(0) }
                    if !viewModel.item.isEmpty {
                        clearButton { viewModel.item = "" }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            lengthHint(for: viewModel.item, state: viewModel.itemLengthState)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.itemLengthState == .ok)
    }

    // MARK: - Set Picker Section

    private var setPickerSection: some View {
        fieldSection(label: "SET") {
            if viewModel.isCreatingNewSet {
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
                    viewModel.selectedSetId = set.id
                } label: {
                    HStack {
                        Text(set.name)
                        if viewModel.selectedSetId == set.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                viewModel.selectedSetId = nil
                viewModel.isCreatingNewSet = true
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
                    .foregroundStyle(viewModel.selectedSetId == nil
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
                TextField("Set name", text: $viewModel.newSetName)
                    .font(.body)
                    .focused($focused, equals: .newSetName)
                    .submitLabel(.next)
                    .onSubmit { focused = .sampleEN(0) }
                if !viewModel.newSetName.isEmpty {
                    clearButton { viewModel.newSetName = "" }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !userSets.isEmpty {
                Divider()
                Button {
                    viewModel.newSetName = ""
                    viewModel.isCreatingNewSet = false
                    viewModel.selectedSetId = viewModel.originalSetId ?? viewModel.preselectedSetId
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
        if !viewModel.en.trimmingCharacters(in: .whitespaces).isEmpty
            && (viewModel.isAutoFilling || viewModel.hasEmptyAutoFillFields) {
            Button {
                focused = nil // dismiss keyboard before filling
                viewModel.startAutoFill()
            } label: {
                Group {
                    if viewModel.isAutoFilling {
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
                .padding(.horizontal, viewModel.isAutoFilling ? 14 : 20)
                .padding(.vertical, 14)
                .overlay { Capsule().strokeBorder(Color.myColors.myBlue, lineWidth: 1.5) }
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: viewModel.isAutoFilling)
        }
    }

    // MARK: - Example Sections

    private var examplesENSection: some View {
        fieldSection(label: "ENGLISH EXAMPLES") {
            examplesList(samples: $viewModel.samplesEN, fieldTag: { .sampleEN($0) }, isLastSection: false)
        }
    }

    private var examplesItemSection: some View {
        fieldSection(label: "NATIVE EXAMPLES") {
            examplesList(samples: $viewModel.samplesItem, fieldTag: { .sampleItem($0) }, isLastSection: true)
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
                                var updated = samples.wrappedValue
                                updated.remove(at: i)
                                samples.wrappedValue = updated
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

            if !samples.wrappedValue.isEmpty { Divider() }

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

    // MARK: - Length Hint

    @ViewBuilder
    private func lengthHint(for text: String, state: CardLengthState) -> some View {
        let count = text.trimmingCharacters(in: .whitespaces).count
        let warn  = CardLengthValidator.warningLength
        let max   = CardLengthValidator.maxLength
        switch state {
        case .ok:
            // Появляется только когда пользователь приближается к лимиту (> 30 символов)
            if count > 30 {
                Text("\(count) / \(warn)")
                    .font(.caption)
                    .foregroundStyle(Color.myColors.mySecondary)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }
        case .warning:
            Label("Long phrase — cards work best with short words (\(count)/\(max))",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Color.myColors.myOrange)
                .padding(.horizontal, 20)
                .transition(.opacity)
        case .tooLong:
            Label("Too long for a card — shorten to \(max) characters or less (\(count)/\(max))",
                  systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(Color.myColors.myRed)
                .padding(.horizontal, 20)
                .transition(.opacity)
        }
    }

    // MARK: - Clear Button

    private func clearButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
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
            .frame(maxWidth: 360)
            .padding(.horizontal, 40)
        }
    }
}
