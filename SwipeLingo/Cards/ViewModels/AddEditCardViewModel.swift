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

    /// Пользовательские Sets, кроме Inbox. Двойная фильтрация — по CardSet.isUserCreated
    /// И по parent Collection.isUserCreated — чтобы покрыть legacy-дефолты миграции.
    func userSets(allSets: [CardSet], allCollections: [Collection]) -> [CardSet] {
        let userCollectionIds = Set(allCollections.filter { $0.isUserCreated }.map { $0.id })
        return allSets.filter {
            $0.isUserCreated &&
            userCollectionIds.contains($0.collectionId) &&
            $0.name != "Inbox"
        }
    }

    func selectedSetName(allSets: [CardSet], allCollections: [Collection]) -> String {
        guard let id = selectedSetId else { return "Choose or add a new set…" }
        return userSets(allSets: allSets, allCollections: allCollections)
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
        if isEditMode {
            return enOK && hasChanges          // активна только когда что-то изменилось
        }
        if isCreatingNewSet {
            return enOK && !newSetName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return enOK && selectedSetId != nil
    }

    // MARK: - Save

    /// Применяет working copy к `originalCard`, либо вставляет новую `Card` — при необходимости
    /// сперва создавая новый `CardSet` (когда выбрано "New set…").
    /// - Returns: false, если новый Set требуется, но его имя пустое — вызывающая сторона
    ///   не должна закрывать экран в этом случае.
    @discardableResult
    func handleSave(context: ModelContext, allCollections: [Collection]) -> Bool {
        let enClean   = en.trimmingCharacters(in: .whitespaces)
        let itemClean = item.trimmingCharacters(in: .whitespaces)
        let snEN   = samplesEN.map   { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let snItem = samplesItem.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if let original = originalCard {
            original.en         = enClean
            original.item       = itemClean
            original.sampleEN   = snEN
            original.sampleItem = snItem
            if let newSetId = resolveSetId(context: context, allCollections: allCollections) {
                original.setId = newSetId
            }
        } else {
            guard let setId = resolveSetId(context: context, allCollections: allCollections) else { return false }
            let card = Card(en: enClean, item: itemClean,
                            sampleEN: snEN, sampleItem: snItem, setId: setId)
            context.insert(card)
        }
        context.saveWithErrorHandling()
        return true
    }

    /// Возвращает целевой setId; создаёт новый CardSet, если isCreatingNewSet.
    private func resolveSetId(context: ModelContext, allCollections: [Collection]) -> UUID? {
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
}
