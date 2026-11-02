import SwiftUI
import SwiftData
import Translation

// MARK: - AddEditCardViewModel
//
// Вся бизнес-логика AddEditCardView: working copy карточки, выбор/создание Set,
// валидация (длина, дубликаты) и auto-fill (Free Dictionary + Apple Translation).
// Перенесена из AddEditCardView как есть — механический перенос без изменения логики.
//
// @Query-результаты (allSets/allCollections/allCards) не копируются в VM — ModelContext
// недоступен как @Environment вне View, а сами массивы должны оставаться "живыми"
// (обновляться вместе с SwiftData), поэтому передаются параметром на каждый вызов —
// тот же паттерн, что уже используется в PileBuilderViewModel.saveAndActivate(context:allPiles:).

@Observable
final class AddEditCardViewModel {

    // MARK: Mode & snapshot

    /// Редактируемая карточка, либо nil в режиме создания.
    let originalCard: Card?
    /// setId, зафиксированный при инициализации — используется чтобы понять, что карточку перенесли в другой Set.
    let originalSetId: UUID?
    /// Set, который нужно предвыбрать в режиме создания (например, открыто изнутри конкретного CardSet).
    let preselectedSetId: UUID?

    // MARK: Working copy

    var en: String
    var item: String
    var samplesEN: [String]
    var samplesItem: [String]

    // MARK: Set picker

    var selectedSetId: UUID?
    var isCreatingNewSet: Bool = false
    var newSetName: String = ""
    /// Коллекция, в которой будет создан новый сет (кнопка «Add set»).
    var newSetCollectionId: UUID?

    // MARK: Auto-fill (dictionary + Apple Translation)

    var translationSession: TranslationSession?
    var translationConfig: TranslationSession.Configuration?
    var isAutoFilling = false
    private var autoFillTask: Task<Void, Never>?

    // MARK: - Init

    /// - Parameters:
    ///   - card: карточка для редактирования, либо nil для создания новой.
    ///   - preselectedSetId: Set, который нужно предвыбрать в режиме создания.
    init(card: Card?, preselectedSetId: UUID?) {
        originalCard = card
        originalSetId = card?.setId
        self.preselectedSetId = preselectedSetId

        en = card?.en ?? ""
        item = card?.item ?? ""
        samplesEN = card?.sampleEN ?? []
        samplesItem = card?.sampleItem ?? []
        selectedSetId = card?.setId ?? preselectedSetId
    }

    // MARK: - Computed

    var isEditMode: Bool { originalCard != nil }

    /// Кнопка auto-fill видна пока есть хотя бы одно незаполненное поле.
    var hasEmptyAutoFillFields: Bool {
        item.trimmingCharacters(in: .whitespaces).isEmpty
        || samplesEN.allSatisfy   { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        || samplesItem.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Сеты из своих коллекций пользователя (см. `targetCollections`) — без системной коллекции Inbox
    /// и, значит, без Inbox: Inbox — отдельная сущность, в пикере карточки его нет. Двойная
    /// фильтрация — по CardSet.isUserCreated И по parent Collection — чтобы покрыть
    /// legacy-дефолты миграции.
    func userSets(allSets: [CardSet], allCollections: [Collection], firebaseUID: String) -> [CardSet] {
        let userCollectionIds = Set(targetCollections(allCollections: allCollections, firebaseUID: firebaseUID).map(\.id))
        return allSets.filter { $0.isUserCreated && userCollectionIds.contains($0.collectionId) }
    }

    /// Коллекции, в которых можно создать сет: пользовательские и свои, кроме системной коллекции Inbox
    /// (контейнер Inbox). `firebaseUID` отсекает чужие коллекции, оставшиеся локально после гонки
    /// CloudKit (см. `Collection.isMine(firebaseUID:)`).
    func targetCollections(allCollections: [Collection], firebaseUID: String) -> [Collection] {
        allCollections.filter { $0.isUserCreated && !$0.isInbox && $0.isMine(firebaseUID: firebaseUID) }
    }

    /// Начинает ввод нового сета: коллекция по умолчанию — коллекция выбранного сета, если он
    /// в своей коллекции, иначе первая из `targetCollections` (`nil`, если своих коллекций нет).
    /// Выбранный сет не сбрасывается — «Back» возвращает к нему.
    func beginNewSet(allSets: [CardSet], allCollections: [Collection], firebaseUID: String) {
        isCreatingNewSet = true
        newSetName = ""
        let targets = targetCollections(allCollections: allCollections, firebaseUID: firebaseUID)
        let selectedCollectionId = allSets.first { $0.id == selectedSetId }?.collectionId
        newSetCollectionId = targets.first { $0.id == selectedCollectionId }?.id ?? targets.first?.id
    }

    /// Подставляет первую из своих коллекций, если выбранной для нового сета нет среди них —
    /// например, пользователь только что создал первую коллекцию прямо из этого экрана.
    func ensureNewSetCollection(allCollections: [Collection], firebaseUID: String) {
        let targets = targetCollections(allCollections: allCollections, firebaseUID: firebaseUID)
        guard !targets.contains(where: { $0.id == newSetCollectionId }) else { return }
        newSetCollectionId = targets.first?.id
    }

    /// Можно ли нажать «Add set»: имя не пустое, коллекция своя, и в ней ещё нет сета с таким
    /// именем (без учёта регистра).
    func canAddNewSet(allSets: [CardSet], allCollections: [Collection], firebaseUID: String) -> Bool {
        let name = newSetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              let collectionId = newSetCollectionId,
              targetCollections(allCollections: allCollections, firebaseUID: firebaseUID).contains(where: { $0.id == collectionId })
        else { return false }
        return !allSets.contains {
            $0.collectionId == collectionId && !$0.isSoftDeleted && $0.name.lowercased() == name.lowercased()
        }
    }

    /// Создаёт сет сразу (не при Save карточки) в выбранной коллекции и делает его выбранным;
    /// блок SET возвращается к пикеру. Если карточку потом отменят, сет остаётся — его создание
    /// было явным действием пользователя.
    /// - Returns: false, если добавить нельзя (см. `canAddNewSet`).
    @discardableResult
    func addNewSet(context: ModelContext, allSets: [CardSet], allCollections: [Collection], firebaseUID: String) -> Bool {
        guard canAddNewSet(allSets: allSets, allCollections: allCollections, firebaseUID: firebaseUID),
              let collectionId = newSetCollectionId
        else { return false }
        let newSet = CardSet(name: newSetName.trimmingCharacters(in: .whitespaces), collectionId: collectionId, isUserCreated: true)
        context.insert(newSet)
        context.saveWithErrorHandling()
        selectedSetId = newSet.id
        isCreatingNewSet = false
        newSetName = ""
        return true
    }

    func selectedSetName(allSets: [CardSet], allCollections: [Collection], firebaseUID: String) -> String {
        guard let id = selectedSetId else { return "Choose or add a new set…" }
        return userSets(allSets: allSets, allCollections: allCollections, firebaseUID: firebaseUID)
            .first(where: { $0.id == id })?.name ?? "Choose a set"
    }

    /// true, если working copy отличается от исходного снимка (в режиме создания — если
    /// хоть что-то заполнено).
    var hasChanges: Bool {
        let enTrim   = en.trimmingCharacters(in: .whitespaces)
        let itemTrim = item.trimmingCharacters(in: .whitespaces)
        let snEN   = samplesEN.map   { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let snItem = samplesItem.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        guard let original = originalCard else {
            // Add mode — любое заполненное поле считается изменением
            return !enTrim.isEmpty || !itemTrim.isEmpty ||
                   !newSetName.isEmpty || selectedSetId != preselectedSetId ||
                   snEN.contains(where: { !$0.isEmpty }) ||
                   snItem.contains(where: { !$0.isEmpty })
        }
        // Edit mode — сравниваем working copy с исходным снимком
        return enTrim != original.en    ||
               itemTrim != original.item ||
               snEN != original.sampleEN ||
               snItem != original.sampleItem ||
               selectedSetId != originalSetId
    }

    // MARK: Length Validation (via CardLengthValidator)

    var enLengthState:   CardLengthState { CardLengthValidator.state(for: en) }
    var itemLengthState: CardLengthState { CardLengthValidator.state(for: item) }

    /// true, если `en` уже существует (без учёта регистра) в целевом Set — используется как
    /// мягкое предупреждение, сохранение не блокирует.
    func isDuplicateEN(allCards: [Card]) -> Bool {
        guard let setId = selectedSetId, !isCreatingNewSet,
              !en.trimmingCharacters(in: .whitespaces).isEmpty
        else { return false }
        let enLower = en.trimmingCharacters(in: .whitespaces).lowercased()
        return allCards.contains {
            $0.setId == setId &&
            $0.en.lowercased() == enLower &&
            $0.id != originalCard?.id
        }
    }

    var canSave: Bool {
        let enOK = !en.trimmingCharacters(in: .whitespaces).isEmpty
        guard enLengthState != .tooLong, itemLengthState != .tooLong else { return false }
        // Пока вводится новый сет, сохранять нельзя: сет создаётся только кнопкой «Add set»,
        // иначе карточка молча ушла бы в прежний выбранный сет.
        guard !isCreatingNewSet else { return false }
        if isEditMode {
            return enOK && hasChanges          // активна только когда что-то изменилось
        }
        return enOK && selectedSetId != nil
    }

    // MARK: - Save

    /// Применяет working copy к `originalCard`, либо вставляет новую `Card` в выбранный сет.
    /// Новый сет здесь не создаётся — только кнопкой «Add set» (`addNewSet`).
    /// - Returns: false, если для новой карточки не выбран сет — вызывающая сторона
    ///   не должна закрывать экран в этом случае.
    @discardableResult
    func handleSave(context: ModelContext) -> Bool {
        let enClean   = en.trimmingCharacters(in: .whitespaces)
        let itemClean = item.trimmingCharacters(in: .whitespaces)
        let snEN   = samplesEN.map   { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let snItem = samplesItem.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if let original = originalCard {
            original.en         = enClean
            original.item       = itemClean
            original.sampleEN   = snEN
            original.sampleItem = snItem
            if let newSetId = selectedSetId {
                original.setId = newSetId
            }
        } else {
            guard let setId = selectedSetId else { return false }
            let card = Card(en: enClean, item: itemClean,
                            sampleEN: snEN, sampleItem: snItem, setId: setId)
            context.insert(card)
        }
        context.saveWithErrorHandling()
        return true
    }

    // MARK: - Auto-fill

    /// Строит (или пересобирает — например, после смены языка) конфигурацию Apple Translation
    /// для auto-fill. На симуляторе — no-op, Apple Translation там недоступен.
    func buildTranslationConfig(nativeLanguage: NativeLanguage) {
        #if !targetEnvironment(simulator)
        log("buildTranslationConfig: nativeLanguage=\(nativeLanguage.langId)", level: .info)
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: nativeLanguage.langId)
        )
        #else
        log("buildTranslationConfig: skipped on simulator", level: .warning)
        #endif
    }

    /// Запускает auto-fill, если он ещё не выполняется. Task хранится внутри VM и отменяется
    /// через `cancelAutoFillTask()` — вызывать из `.onDisappear` View.
    func startAutoFill() {
        guard !isAutoFilling else { return }
        autoFillTask = Task { await performAutoFill() }
    }

    /// Отменяет незавершённый auto-fill task.
    func cancelAutoFillTask() {
        autoFillTask?.cancel()
    }

    /// Загружает примеры из словаря и переводы Apple Translation; заполняет только пустые поля.
    private func performAutoFill() async {
        let word = en.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        isAutoFilling = true
        defer { isAutoFilling = false }

        log("handleAutoFill: word='\(word)', session=\(translationSession == nil ? "nil ❌" : "ready ✓")", level: .info)

        // Apple Translation готовит session асинхронно (.translationTask во View) — при первом
        // открытии шита или первом использовании языковой пары это заметно небыстро. Если
        // пользователь тапнул Auto-fill раньше, чем session успела прийти, — ждём её появления
        // с ограниченным таймаутом, а не пропускаем перевод навсегда без единой попытки.
        if translationConfig != nil, translationSession == nil {
            await waitForTranslationSession()
            log("handleAutoFill: after wait, session=\(translationSession == nil ? "nil ❌" : "ready ✓")", level: .info)
        }

        // Шаг 1: перевести само слово → заполнить item, если пусто
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

        // Шаг 2: получить EN-примеры из словаря, если пусто
        let isENEmpty = samplesEN.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        if isENEmpty {
            do {
                let entry = try await DictionaryService().lookup(word: word)
                // Предпочитаем примеры-предложения; если их нет — берём текст определения.
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
                // Только описание: в самой ошибке сети лежит URL запроса (у MW — с ключом API).
                if !DictionaryService.isCancellation(error) {
                    log("dictionary lookup failed: \(error.localizedDescription)", level: .warning)
                }
            }
        }

        guard !Task.isCancelled else { return }

        // Шаг 3: перевести EN-примеры → заполнить примеры на родном языке, если пусто
        // Выполняется независимо от того, были ли EN-примеры только что получены или уже существовали
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

    /// Ждёт появления `translationSession` (устанавливается извне через `.translationTask`)
    /// до `timeout` секунд, опрашивая с шагом `pollInterval`. Возвращается раньше, если
    /// session появилась или task отменён — не блокирует дольше необходимого.
    private func waitForTranslationSession(timeout: TimeInterval = 3.0, pollInterval: UInt64 = 150_000_000) async {
        let deadline = Date().addingTimeInterval(timeout)
        while translationSession == nil, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: pollInterval)
        }
    }
}
