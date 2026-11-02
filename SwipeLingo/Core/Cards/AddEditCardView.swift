import SwiftUI
import SwiftData
import Translation
import FirebaseAuth

// MARK: - AddEditCardView
// Единый sheet добавления / редактирования Card.
//
// Режим добавления (card == nil):
//   • preselectedSetId — опционален, предзаполняет выбор сета
//   • userSets пуст   — сразу ввод нового сета: имя + коллекция + «Add set» (сет создаётся
//                       сразу и становится выбранным); без своих коллекций — «New Collection»
//   • userSets непуст — Menu-пикер; опция "New set…" внизу
//
// Режим редактирования (card != nil):
//   • Working copy сравнивается с исходным снимком
//   • checkmark активен только при наличии изменений
//   • xmark показывает подтверждение только при наличии изменений
//   • Секция SET доступна — карточку можно перенести в другой сет
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

    @State private var vm: AddEditCardViewModel

    @State private var isShowingExitConfirm = false
    @State private var isShowingAddCollection = false
    @FocusState private var focused: Field?

    /// Передаётся из composition root — не через .environment().
    private let appSyncStateService: AppSyncStateService
    /// Нужен только для `firebaseUID` — отсечь чужие "My Sets"/сеты, оставшиеся
    /// локально после гонки CloudKit (см. `Collection.isMine(firebaseUID:)`).
    private let authService: AuthFBService
    private var firebaseUID: String { authService.currentUser?.uid ?? "" }
    // Auto-fill (dictionary + Apple Translation)
    // Единственный источник правды — AppSyncStateService.nativeLanguage (SwiftData + CloudKit-синк).
    private var nativeLanguage: NativeLanguage { appSyncStateService.nativeLanguage }

    // Keyboard
    @State private var keyboard = KeyboardManager()

    enum Field: Hashable {
        case en, item, newSetName
        case sampleEN(Int), sampleItem(Int)
    }

    // MARK: - Init

    init(card: Card? = nil, preselectedSetId: UUID? = nil, appSyncStateService: AppSyncStateService, authService: AuthFBService) {
        _vm = State(initialValue: AddEditCardViewModel(card: card, preselectedSetId: preselectedSetId))
        self.appSyncStateService = appSyncStateService
        self.authService = authService
    }

    // MARK: - Computed (делегируют в VM, добавляя @Query-результаты)

    private var userSets: [CardSet] {
        vm.userSets(allSets: allSets, allCollections: allCollections, firebaseUID: firebaseUID)
    }

    private var selectedSetName: String {
        vm.selectedSetName(allSets: allSets, allCollections: allCollections, firebaseUID: firebaseUID)
    }

    private var isDuplicateEN: Bool {
        vm.isDuplicateEN(allCards: allCards)
    }

    private var targetCollections: [Collection] {
        vm.targetCollections(allCollections: allCollections, firebaseUID: firebaseUID)
    }

    private var canAddNewSet: Bool {
        vm.canAddNewSet(allSets: allSets, allCollections: allCollections, firebaseUID: firebaseUID)
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
            .background(Color.myColors.mySheetBackground.ignoresSafeArea())
            .sheetNavigationBar(vm.isEditMode ? "Edit Card" : "New Card")
            .navigationBarBackButtonHidden(true)
            .toolbar { toolbarContent }
            .overlay { if isShowingExitConfirm { exitConfirmOverlay } }
            .onAppear {
                focused = nil // предотвращаем всплытие клавиатуры при старте
                if !vm.isEditMode && userSets.isEmpty {
                    vm.beginNewSet(allSets: allSets, allCollections: allCollections, firebaseUID: firebaseUID)
                }
                vm.buildTranslationConfig(nativeLanguage: nativeLanguage)
            }
            .onDisappear {
                vm.cancelAutoFillTask()
            }
            .sheet(isPresented: $isShowingAddCollection) {
                AddCollectionView()
            }
            // Коллекция, созданная прямо отсюда («New Collection»), сразу становится целью нового сета.
            .onChange(of: targetCollections.map(\.id)) { _, _ in
                vm.ensureNewSetCollection(allCollections: allCollections, firebaseUID: firebaseUID)
            }
            .translationTask(vm.translationConfig) { session in
                log("translationTask: session received ✓", level: .info)
                vm.translationSession = session
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
                    .background(Color.myColors.mySheetBackground)
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
        
        ToolbarItem(placement: .cancellationAction) {
            NavBarButtonForSheet(
                title: "Cancel",
                color: Color.myColors.myRed) {
                    handleCancel()
                }
                .disabled(isShowingExitConfirm)
        }

        ToolbarItem(placement: .confirmationAction) {
            NavBarButtonForSheet(
                title: "Save",
                color: vm.canSave ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.8)) {
                    handleSave()
                }
                .disabled(!vm.canSave || isShowingExitConfirm)
        }

        
//        ToolbarItem(placement: .topBarLeading) {
//            Button(action: handleSave) {
//                Image(systemName: "checkmark")
//                    .font(.subheadline.weight(vm.canSave ? .semibold : .regular))
//                    .foregroundStyle(vm.canSave ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.8))
//            }
//            .disabled(!vm.canSave || isShowingExitConfirm)
//        }
//        ToolbarItem(placement: .topBarTrailing) {
//            Button(action: handleCancel) {
//                Image(systemName: "xmark")
//                    .font(.subheadline.weight(.semibold))
//                    .foregroundStyle(Color.myColors.myRed)
//            }
//            .disabled(isShowingExitConfirm)
//        }
    }

    // MARK: - Actions

    private func handleSave() {
        guard vm.handleSave(context: context) else { return }
        dismiss()
    }

    /// Создаёт новый сет кнопкой «Add set» (или Return в поле имени) и убирает клавиатуру.
    private func addNewSet() {
        guard vm.addNewSet(context: context, allSets: allSets, allCollections: allCollections, firebaseUID: firebaseUID) else { return }
        focused = nil
    }

    private func handleCancel() {
        if vm.hasChanges {
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
                    TextField("Word or phrase", text: $vm.en, axis: .vertical)
                        .font(.body)
                        .focused($focused, equals: .en)
                        .submitLabel(.next)
                        .onSubmit { focused = .item }
                    if !vm.en.isEmpty {
                        clearButton { vm.en = "" }
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
            lengthHint(for: vm.en, state: vm.enLengthState)
        }
        .animation(.easeInOut(duration: 0.2), value: isDuplicateEN)
        .animation(.easeInOut(duration: 0.2), value: vm.enLengthState == .ok)
    }

    private var itemSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldSection(label: "TRANSLATION") {
                HStack(spacing: 8) {
                    TextField("Native translation", text: $vm.item, axis: .vertical)
                        .font(.body)
                        .focused($focused, equals: .item)
                        .submitLabel(.next)
                        .onSubmit { focused = .sampleEN(0) }
                    if !vm.item.isEmpty {
                        clearButton { vm.item = "" }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            lengthHint(for: vm.item, state: vm.itemLengthState)
        }
        .animation(.easeInOut(duration: 0.2), value: vm.itemLengthState == .ok)
    }

    // MARK: - Set Picker Section

    private var setPickerSection: some View {
        fieldSection(label: "SET") {
            if vm.isCreatingNewSet {
                newSetField
            } else {
                existingSetMenu
            }
        }
    }

    /// Menu с существующими пользовательскими сетами + "New set…" внизу
    private var existingSetMenu: some View {
        Menu {
            ForEach(userSets) { set in
                Button {
                    vm.selectedSetId = set.id
                } label: {
                    HStack {
                        Text(set.name)
                        if vm.selectedSetId == set.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                vm.beginNewSet(allSets: allSets, allCollections: allCollections, firebaseUID: firebaseUID)
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
                    .foregroundStyle(vm.selectedSetId == nil
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

    /// Ввод нового сета: имя, коллекция и кнопка «Add set», которая создаёт сет сразу и
    /// возвращает пикер с ним выбранным. Без своих коллекций — предложение сначала создать коллекцию.
    @ViewBuilder
    private var newSetField: some View {
        if targetCollections.isEmpty {
            VStack(spacing: 10) {
                Text("Create a collection first to add sets")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                Button {
                    isShowingAddCollection = true
                } label: {
                    Label("New Collection", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.myColors.myBlue)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("Set name", text: $vm.newSetName)
                        .font(.body)
                        .focused($focused, equals: .newSetName)
                        .submitLabel(.done)
                        .onSubmit { addNewSet() }
                    if !vm.newSetName.isEmpty {
                        clearButton { vm.newSetName = "" }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                newSetCollectionMenu

                Divider()
                HStack {
                    if !userSets.isEmpty {
                        Button {
                            vm.newSetName = ""
                            vm.isCreatingNewSet = false
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.semibold))
                                Text("Back")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(Color.myColors.myBlue)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button {
                        addNewSet()
                    } label: {
                        Text("Add set")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(canAddNewSet ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAddNewSet)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
        }
    }

    /// Строка выбора коллекции для нового сета — только свои коллекции, без системной "My Sets".
    private var newSetCollectionMenu: some View {
        Menu {
            ForEach(targetCollections) { collection in
                Button {
                    vm.newSetCollectionId = collection.id
                } label: {
                    HStack {
                        Text(collection.name)
                        if vm.newSetCollectionId == collection.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text("In collection")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                Spacer()
                Text(targetCollections.first { $0.id == vm.newSetCollectionId }?.name ?? "Choose")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.myColors.myBlue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Auto-fill Button

    @ViewBuilder
    private var autoFillButton: some View {
        if !vm.en.trimmingCharacters(in: .whitespaces).isEmpty
            && (vm.isAutoFilling || vm.hasEmptyAutoFillFields) {
            Button {
                focused = nil // скрываем клавиатуру перед заполнением
                vm.startAutoFill()
            } label: {
                Group {
                    if vm.isAutoFilling {
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
                .padding(.horizontal, vm.isAutoFilling ? 14 : 20)
                .padding(.vertical, 14)
                .overlay { Capsule().strokeBorder(Color.myColors.myBlue, lineWidth: 1.5) }
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: vm.isAutoFilling)
        }
    }

    // MARK: - Example Sections

    private var examplesENSection: some View {
        fieldSection(label: "ENGLISH EXAMPLES") {
            examplesList(samples: $vm.samplesEN, fieldTag: { .sampleEN($0) }, isLastSection: false)
        }
    }

    private var examplesItemSection: some View {
        fieldSection(label: "NATIVE EXAMPLES") {
            examplesList(samples: $vm.samplesItem, fieldTag: { .sampleItem($0) }, isLastSection: true)
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
                .background(Color.myColors.mySheetBackground)
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
