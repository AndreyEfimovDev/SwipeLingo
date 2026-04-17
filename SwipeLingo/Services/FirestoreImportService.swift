import Foundation
import SwiftData

// MARK: - FirestoreImportService
//
// Responsible for importing developer-curated content (Collections → CardSets → Cards).
//
// Current implementation: hardcoded stub — no Firebase SDK required.
// TODO: Replace importStubContent() with real Firestore SDK fetch.
//
// Injected and called once in SwipeLingoApp.init().
// Guard prevents double-import: skips if any developer collection already exists.

struct FirestoreImportService {

    // MARK: - Public API

    func importIfNeeded(into context: ModelContext) {
        let descriptor = FetchDescriptor<Collection>(
            predicate: #Predicate { !$0.isUserCreated }
        )
        let existing = context.fetchCountWithErrorHandling(descriptor)
        guard existing == 0 else { return }

        importStubContent(into: context)
        context.saveWithErrorHandling()
        log("Developer content imported (stub)", level: .info)
    }

    // MARK: - FSCard → Card conversion

    /// Converts an FSCard (Firestore model) into a SwiftData Card.
    /// - Parameters:
    ///   - fsCard: The Firestore card to convert.
    ///   - swiftDataSetId: The SwiftData UUID of the parent CardSet (not the Firestore string ID).
    ///   - language: The user's native language — selects the correct translation from FSCard.
    func card(from fsCard: FSCard, swiftDataSetId: UUID, language: NativeLanguage) -> Card {
        Card(
            en:                fsCard.en,
            item:              fsCard.translation(for: language),
            sampleEN:          fsCard.sampleEN,
            sampleItem:        fsCard.sampleTranslation(for: language),
            dictTranscription: fsCard.transcription,
            setId:             swiftDataSetId
        )
    }

    // MARK: - Stub implementation
    // TODO: Delete importStubContent() and implement fetchFromFirestore() instead.

    private func importStubContent(into context: ModelContext) {

        // ─────────────────────────────────────────────
        // Collection 1 — IELTS Vocabulary
        // ─────────────────────────────────────────────

        let ielts = Collection(
            name: "IELTS Vocabulary",
            icon: "book",
            isOwned: true,
            isUserCreated: false
        )
        context.insert(ielts)

        let academicSet = CardSet(
            name: "Academic Words",
            collectionId: ielts.id,
            level: .b2,
            isUserCreated: false,
            setDescription: "25 high-frequency academic words drawn from the IELTS word list. Covers verbs, adjectives and nouns that appear across all four IELTS papers."
        )
        context.insert(academicSet)
        let sid = academicSet.id

        let academicCards: [Card] = [
            Card(en: "Serendipity",    item: "счастливая случайность",
                 sampleEN:   ["It was pure serendipity that we met at the airport."],
                 sampleItem: ["Наша встреча в аэропорту была чистой случайностью."],
                 setId: sid),
            Card(en: "Resilience",    item: "стойкость, жизнестойкость",
                 sampleEN:   ["Her resilience in the face of adversity inspired everyone."],
                 sampleItem: ["Её стойкость перед лицом невзгод вдохновляла всех."],
                 setId: sid),
            Card(en: "Ephemeral",     item: "мимолётный, преходящий",
                 sampleEN:   ["Fame can be ephemeral — here today, gone tomorrow."],
                 sampleItem: ["Слава бывает мимолётной — сегодня есть, завтра нет."],
                 setId: sid),
            Card(en: "Eloquent",      item: "красноречивый",
                 sampleEN:   ["She gave an eloquent speech that moved the audience."],
                 sampleItem: ["Она произнесла красноречивую речь, тронувшую зал."],
                 setId: sid),
            Card(en: "Tenacious",     item: "настойчивый, упорный",
                 sampleEN:   ["A tenacious athlete never gives up, no matter the score."],
                 sampleItem: ["Упорный спортсмен никогда не сдаётся, каков бы ни был счёт."],
                 setId: sid),
            Card(en: "Ambiguous",     item: "неоднозначный, двусмысленный",
                 sampleEN:   ["The contract contained several ambiguous clauses."],
                 sampleItem: ["В договоре было несколько неоднозначных пунктов."],
                 setId: sid),
            Card(en: "Paramount",     item: "первостепенный, важнейший",
                 sampleEN:   ["Safety is of paramount importance on a construction site."],
                 sampleItem: ["Безопасность имеет первостепенное значение на стройплощадке."],
                 setId: sid),
            Card(en: "Melancholy",    item: "меланхолия, грусть",
                 sampleEN:   ["A deep melancholy settled over him as autumn arrived."],
                 sampleItem: ["С приходом осени им овладела глубокая меланхолия."],
                 setId: sid),
            Card(en: "Ubiquitous",    item: "вездесущий, повсеместный",
                 sampleEN:   ["Smartphones have become ubiquitous in modern society."],
                 sampleItem: ["Смартфоны стали повсеместными в современном обществе."],
                 setId: sid),
            Card(en: "Pragmatic",     item: "прагматичный, практичный",
                 sampleEN:   ["We need a pragmatic approach to solve this budget issue."],
                 sampleItem: ["Нам нужен прагматичный подход для решения этой бюджетной проблемы."],
                 setId: sid),
            Card(en: "Mitigate",      item: "смягчать, уменьшать",
                 sampleEN:   ["Planting trees can help mitigate the effects of climate change."],
                 sampleItem: ["Посадка деревьев может помочь смягчить последствия изменения климата."],
                 setId: sid),
            Card(en: "Exacerbate",    item: "усугублять, обострять",
                 sampleEN:   ["Poor sleep can exacerbate feelings of anxiety."],
                 sampleItem: ["Плохой сон может усугублять чувство тревоги."],
                 setId: sid),
            Card(en: "Meticulous",    item: "скрупулёзный, педантичный",
                 sampleEN:   ["The scientist kept meticulous records of every experiment."],
                 sampleItem: ["Учёный вёл скрупулёзные записи каждого эксперимента."],
                 setId: sid),
            Card(en: "Alleviate",     item: "облегчать, смягчать",
                 sampleEN:   ["Exercise can alleviate symptoms of mild depression."],
                 sampleItem: ["Физические упражнения могут облегчить симптомы лёгкой депрессии."],
                 setId: sid),
            Card(en: "Deteriorate",   item: "ухудшаться, деградировать",
                 sampleEN:   ["Air quality in the city continues to deteriorate each year."],
                 sampleItem: ["Качество воздуха в городе продолжает ухудшаться каждый год."],
                 setId: sid),
            Card(en: "Facilitate",    item: "облегчать, способствовать",
                 sampleEN:   ["The new software will facilitate communication between teams."],
                 sampleItem: ["Новое программное обеспечение облегчит коммуникацию между командами."],
                 setId: sid),
            Card(en: "Coherent",      item: "связный, последовательный",
                 sampleEN:   ["Please present your ideas in a coherent and logical order."],
                 sampleItem: ["Пожалуйста, изложите свои идеи в связном и логичном порядке."],
                 setId: sid),
            Card(en: "Substantial",   item: "существенный, значительный",
                 sampleEN:   ["The company made a substantial profit in the third quarter."],
                 sampleItem: ["Компания получила существенную прибыль в третьем квартале."],
                 setId: sid),
            Card(en: "Conspicuous",   item: "заметный, бросающийся в глаза",
                 sampleEN:   ["The bright red car was conspicuous in the grey parking lot."],
                 sampleItem: ["Ярко-красная машина выделялась на сером парковочном месте."],
                 setId: sid),
            Card(en: "Benevolent",    item: "доброжелательный, благосклонный",
                 sampleEN:   ["The benevolent donor funded a new wing of the hospital."],
                 sampleItem: ["Благожелательный спонсор профинансировал новый корпус больницы."],
                 setId: sid),
            Card(en: "Vindicate",     item: "оправдывать, реабилитировать",
                 sampleEN:   ["New evidence finally vindicated the wrongly accused man."],
                 sampleItem: ["Новые доказательства наконец оправдали несправедливо обвинённого человека."],
                 setId: sid),
            Card(en: "Disparate",     item: "разрозненный, несхожий",
                 sampleEN:   ["The committee included people from disparate backgrounds."],
                 sampleItem: ["В состав комиссии вошли люди из разных слоёв общества."],
                 setId: sid),
            Card(en: "Profound",      item: "глубокий, значительный",
                 sampleEN:   ["Losing his job had a profound impact on his sense of identity."],
                 sampleItem: ["Потеря работы оказала глубокое влияние на его ощущение себя."],
                 setId: sid),
            Card(en: "Inevitable",    item: "неизбежный, неотвратимый",
                 sampleEN:   ["Some degree of conflict in a team is inevitable."],
                 sampleItem: ["Определённая степень конфликта в команде неизбежна."],
                 setId: sid),
            Card(en: "Implications",  item: "последствия, подтекст",
                 sampleEN:   ["The researchers discussed the broader implications of their findings."],
                 sampleItem: ["Исследователи обсудили более широкие последствия своих открытий."],
                 setId: sid),
        ]
        for card in academicCards { context.insert(card) }

        // ── IELTS Set 2: Writing Task 2 Phrases ─────────

        let writingSet = CardSet(
            name: "Writing Task 2",
            collectionId: ielts.id,
            level: .b2,
            isUserCreated: false,
            setDescription: "10 advanced linking words and expressions for IELTS Writing Task 2 essays. Master these to raise your Lexical Resource band score."
        )
        context.insert(writingSet)
        let wid = writingSet.id

        let writingCards: [Card] = [
            Card(en: "Notwithstanding", item: "несмотря на, тем не менее",
                 sampleEN:   ["Notwithstanding the challenges, the project was completed on time."],
                 sampleItem: ["Несмотря на трудности, проект был завершён в срок."],
                 setId: wid),
            Card(en: "Albeit",          item: "хотя, пусть и",
                 sampleEN:   ["The policy was effective, albeit controversial among critics."],
                 sampleItem: ["Политика была эффективной, хотя и вызывала споры среди критиков."],
                 setId: wid),
            Card(en: "Hitherto",        item: "до сих пор, прежде",
                 sampleEN:   ["Hitherto unknown species were discovered in the deep ocean."],
                 sampleItem: ["В глубинах океана были обнаружены до сих пор неизвестные виды."],
                 setId: wid),
            Card(en: "Insofar as",      item: "в той мере, в какой; постольку поскольку",
                 sampleEN:   ["The law applies insofar as it does not conflict with human rights."],
                 sampleItem: ["Закон применяется в той мере, в какой он не противоречит правам человека."],
                 setId: wid),
            Card(en: "Paradoxically",   item: "как ни парадоксально",
                 sampleEN:   ["Paradoxically, working fewer hours can increase overall productivity."],
                 sampleItem: ["Как ни парадоксально, меньшее количество рабочих часов может повысить общую продуктивность."],
                 setId: wid),
            Card(en: "Irrefutable",     item: "неопровержимый",
                 sampleEN:   ["The prosecution presented irrefutable evidence of the defendant's guilt."],
                 sampleItem: ["Обвинение представило неопровержимые доказательства вины подсудимого."],
                 setId: wid),
            Card(en: "Proliferation",   item: "распространение, разрастание",
                 sampleEN:   ["The proliferation of social media has changed how people consume news."],
                 sampleItem: ["Распространение социальных сетей изменило то, как люди потребляют новости."],
                 setId: wid),
            Card(en: "Contentious",     item: "спорный, вызывающий разногласия",
                 sampleEN:   ["Capital punishment remains a contentious issue in many democracies."],
                 sampleItem: ["Смертная казнь остаётся спорным вопросом во многих демократических странах."],
                 setId: wid),
            Card(en: "Holistic",        item: "целостный, комплексный",
                 sampleEN:   ["A holistic approach to education addresses academic and emotional needs."],
                 sampleItem: ["Целостный подход к образованию учитывает как академические, так и эмоциональные потребности."],
                 setId: wid),
            Card(en: "Incumbent",       item: "обязательный; занимающий должность",
                 sampleEN:   ["It is incumbent on governments to protect the rights of all citizens."],
                 sampleItem: ["На правительствах лежит обязанность защищать права всех граждан."],
                 setId: wid),
        ]
        for card in writingCards { context.insert(card) }

        // ─────────────────────────────────────────────
        // Collection 2 — Psychology & Mind
        // ─────────────────────────────────────────────

        let psych = Collection(
            name: "Psychology & Mind",
            icon: "brain.head.profile",
            isOwned: true,
            isUserCreated: false
        )
        context.insert(psych)

        let biasSet = CardSet(
            name: "Cognitive Biases",
            collectionId: psych.id,
            level: .c1,
            isUserCreated: false,
            setDescription: "Six core concepts from cognitive psychology and behavioural economics. Understanding these biases improves critical thinking and helps you recognise flawed reasoning."
        )
        context.insert(biasSet)
        let bid = biasSet.id

        let biasCards: [Card] = [
            Card(en: "Confirmation bias",    item: "предвзятость подтверждения",
                 sampleEN:   [
                    "Confirmation bias leads us to favour information that supports our existing beliefs.",
                    "Avoiding confirmation bias requires actively seeking opposing viewpoints."
                 ],
                 sampleItem: [
                    "Предвзятость подтверждения заставляет нас отдавать предпочтение информации, подкрепляющей наши убеждения.",
                    "Чтобы избежать предвзятости подтверждения, нужно активно искать противоположные точки зрения."
                 ],
                 setId: bid),
            Card(en: "Cognitive dissonance", item: "когнитивный диссонанс",
                 sampleEN:   ["He felt cognitive dissonance when his actions contradicted his values."],
                 sampleItem: ["Он испытал когнитивный диссонанс, когда его поступки противоречили его ценностям."],
                 setId: bid),
            Card(en: "Heuristic",            item: "эвристика; практический приём",
                 sampleEN:   ["Using a simple heuristic, she made a quick decision without all the facts."],
                 sampleItem: ["Используя простую эвристику, она быстро приняла решение, не располагая всей информацией."],
                 setId: bid),
            Card(en: "Anchoring effect",     item: "эффект якоря",
                 sampleEN:   ["The high initial price created an anchoring effect on buyers' perception of value."],
                 sampleItem: ["Высокая первоначальная цена создала эффект якоря в восприятии покупателями ценности товара."],
                 setId: bid),
            Card(en: "Introspection",        item: "интроспекция, самоанализ",
                 sampleEN:   ["Regular introspection helps you understand your own motivations and fears."],
                 sampleItem: ["Регулярный самоанализ помогает понять собственные мотивы и страхи."],
                 setId: bid),
            Card(en: "Metacognition",        item: "метакогниция; мышление о мышлении",
                 sampleEN:   ["Metacognition — thinking about how you think — is a key skill for effective learning."],
                 sampleItem: ["Метакогниция — умение размышлять о собственном мышлении — ключевой навык для эффективного обучения."],
                 setId: bid),
        ]
        for card in biasCards { context.insert(card) }

        // ─────────────────────────────────────────────
        // Default Pile — Morning Session
        // ─────────────────────────────────────────────

        let pile = Pile(
            name: "Morning Session",
            setIds: [academicSet.id, biasSet.id],
            isActive: true,
            shuffleMethod: .random
        )
        context.insert(pile)
    }
}
