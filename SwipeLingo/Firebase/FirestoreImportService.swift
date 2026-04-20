import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - FirestoreImportService
//
// Imports and syncs developer-curated content from Firestore into SwiftData.
//
// Two entry points:
//   • importIfNeeded(into:)  — synchronous, uses hardcoded stub content.
//                              Called from SwipeLingoApp.init() as a baseline
//                              so the app has content even without network access.
//                              Runs ONCE (skipped if any developer collection exists).
//
//   • syncFromFirestore(into:language:) — async, fetches real content from Firestore.
//                              Idempotent: uses firestoreId for upsert matching.
//                              Preserves user-modified fields (SRS state, etc.).
//                              Called from SwipeLingoApp as a background Task.
//
// ⚠️  syncFromFirestore requires FirebaseApp.configure() to have been called
//     and GoogleService-Info.plist to be present. If not, it skips gracefully.

struct FirestoreImportService {

    // MARK: - Sync from Firestore (real content)

    func syncFromFirestore(into context: ModelContext, language: NativeLanguage) async {
        guard FirebaseApp.app() != nil else {
            log("[Firestore] Firebase not configured — skipping content sync", level: .warning)
            return
        }

        let db = Firestore.firestore()
        log("[Firestore] Starting content sync…", level: .info)

        do {
            // Pre-load existing developer content indexed by firestoreId
            let allCollections = context.fetchWithErrorHandling(
                FetchDescriptor<Collection>(predicate: #Predicate { !$0.isUserCreated })
            )
            let allSets = context.fetchWithErrorHandling(
                FetchDescriptor<CardSet>(predicate: #Predicate { !$0.isUserCreated })
            )
            let allPairsSets = context.fetchWithErrorHandling(
                FetchDescriptor<PairsSet>()
            )

            var collectionsByFsId: [String: Collection] = Dictionary(
                uniqueKeysWithValues: allCollections.compactMap { c in c.firestoreId.map { ($0, c) } }
            )
            var cardSetsByFsId: [String: CardSet] = Dictionary(
                uniqueKeysWithValues: allSets.compactMap { s in s.firestoreId.map { ($0, s) } }
            )
            var pairsSetsByFsId: [String: PairsSet] = Dictionary(
                uniqueKeysWithValues: allPairsSets.compactMap { s in s.firestoreId.map { ($0, s) } }
            )

            let collSnap = try await db.collection("collections").getDocuments()

            for collDoc in collSnap.documents {
                let d = collDoc.data()
                guard
                    let fsId   = d["id"]   as? String,
                    let name   = d["name"] as? String,
                    let typeRaw = d["type"] as? String,
                    let type   = CollectionType(rawValue: typeRaw)
                else { continue }

                let updatedAt = (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
                let createdAt = (d["createdAt"] as? Timestamp)?.dateValue() ?? .now
                let icon      = d["icon"] as? String

                // Upsert Collection
                let sdCollection: Collection
                if let existing = collectionsByFsId[fsId] {
                    existing.name      = name
                    existing.icon      = icon
                    existing.updatedAt = updatedAt
                    sdCollection = existing
                } else {
                    let c = Collection(
                        name: name, icon: icon,
                        isOwned: true, isUserCreated: false,
                        type: type,
                        updatedAt: updatedAt, createdAt: createdAt
                    )
                    c.firestoreId = fsId
                    context.insert(c)
                    collectionsByFsId[fsId] = c
                    sdCollection = c
                }

                // Sync CardSets
                let setSnap = try await db
                    .collection("collections").document(collDoc.documentID)
                    .collection("cardSets").getDocuments()

                for setDoc in setSnap.documents {
                    let sd = setDoc.data()
                    guard
                        let setFsId = sd["id"]   as? String,
                        let setName = sd["name"] as? String
                    else { continue }

                    let cefrLevel  = (sd["cefrLevel"]  as? String).flatMap { CEFRLevel(rawValue: $0)  } ?? .b2
                    let accessTier = (sd["accessTier"] as? String).flatMap { AccessTier(rawValue: $0) } ?? .free
                    let setUpdatedAt = (sd["updatedAt"] as? Timestamp)?.dateValue() ?? .now
                    let setCreatedAt = (sd["createdAt"] as? Timestamp)?.dateValue() ?? .now
                    let setDesc = sd["description"] as? String

                    // Upsert CardSet
                    let sdSet: CardSet
                    if let existing = cardSetsByFsId[setFsId] {
                        existing.name           = setName
                        existing.cefrLevel      = cefrLevel
                        existing.accessTier     = accessTier
                        existing.setDescription = setDesc
                        existing.updatedAt      = setUpdatedAt
                        sdSet = existing
                    } else {
                        let s = CardSet(
                            name: setName,
                            collectionId: sdCollection.id,
                            level: cefrLevel,
                            isUserCreated: false,
                            accessTier: accessTier,
                            setDescription: setDesc,
                            updatedAt: setUpdatedAt,
                            createdAt: setCreatedAt
                        )
                        s.firestoreId = setFsId
                        context.insert(s)
                        cardSetsByFsId[setFsId] = s
                        sdSet = s
                    }

                    // Sync Cards — load existing once per set
                    let sdSetId = sdSet.id
                    let existingCards = context.fetchWithErrorHandling(
                        FetchDescriptor<Card>(predicate: #Predicate { $0.setId == sdSetId })
                    )
                    var cardsByFsId: [String: Card] = Dictionary(
                        uniqueKeysWithValues: existingCards.compactMap { c in c.firestoreId.map { ($0, c) } }
                    )

                    let cardSnap = try await db
                        .collection("collections").document(collDoc.documentID)
                        .collection("cardSets").document(setDoc.documentID)
                        .collection("cards").getDocuments()

                    for cardDoc in cardSnap.documents {
                        let cd = cardDoc.data()
                        guard
                            let cardFsId = cd["id"] as? String,
                            let en       = cd["en"] as? String
                        else { continue }

                        let translations       = cd["translations"]       as? [String: String]     ?? [:]
                        let sampleEN           = cd["sampleEN"]           as? [String]             ?? []
                        let sampleTranslations = cd["sampleTranslations"] as? [String: [String]]   ?? [:]
                        let transcription      = cd["transcription"]      as? String               ?? ""
                        let tag                = cd["tag"]                as? String               ?? ""
                        let cardUpdatedAt      = (cd["updatedAt"] as? Timestamp)?.dateValue()      ?? .now
                        let cardCreatedAt      = (cd["createdAt"] as? Timestamp)?.dateValue()      ?? .now

                        let item        = translations[language.langId] ?? ""
                        let sampleItem  = sampleTranslations[language.langId] ?? []

                        if let existing = cardsByFsId[cardFsId] {
                            // Update content fields; preserve SRS state and user edits
                            existing.en                = en
                            existing.item              = item
                            existing.sampleEN          = sampleEN
                            existing.sampleItem        = sampleItem
                            existing.dictTranscription = transcription
                            existing.updatedAt         = cardUpdatedAt
                        } else {
                            let c = Card(
                                en: en, item: item,
                                sampleEN: sampleEN, sampleItem: sampleItem,
                                dictTranscription: transcription,
                                createdAt: cardCreatedAt,
                                updatedAt: cardUpdatedAt,
                                setId: sdSet.id
                            )
                            c.firestoreId = cardFsId
                            context.insert(c)
                            cardsByFsId[cardFsId] = c
                        }
                    }
                }

                // Sync PairsSets
                let pairsSnap = try await db
                    .collection("collections").document(collDoc.documentID)
                    .collection("pairsSets").getDocuments()

                for pairsDoc in pairsSnap.documents {
                    let pd = pairsDoc.data()
                    guard let pairsFsId = pd["id"] as? String else { continue }

                    let cefrLevel  = (pd["cefrLevel"]  as? String).flatMap { CEFRLevel(rawValue: $0)  } ?? .b2
                    let accessTier = (pd["accessTier"] as? String).flatMap { AccessTier(rawValue: $0) } ?? .free
                    let title      = pd["title"]       as? String
                    let desc       = pd["description"] as? String
                    let rawItems   = pd["items"]        as? [[String: Any]] ?? []
                    let pairs      = rawItems.compactMap { parsePair(from: $0) }
                    let psUpdatedAt = (pd["updatedAt"] as? Timestamp)?.dateValue() ?? .now
                    let psCreatedAt = (pd["createdAt"] as? Timestamp)?.dateValue() ?? .now

                    if let existing = pairsSetsByFsId[pairsFsId] {
                        existing.title          = title
                        existing.setDescription = desc
                        existing.cefrLevel      = cefrLevel
                        existing.accessTier     = accessTier
                        existing.items          = pairs
                        existing.updatedAt      = psUpdatedAt
                        existing.collectionId   = sdCollection.id
                    } else {
                        let ps = PairsSet(
                            title: title,
                            setDescription: desc,
                            cefrLevel: cefrLevel,
                            accessTier: accessTier,
                            deployStatus: .live,
                            items: pairs,
                            collectionId: sdCollection.id,
                            updatedAt: psUpdatedAt,
                            createdAt: psCreatedAt
                        )
                        ps.firestoreId = pairsFsId
                        context.insert(ps)
                        pairsSetsByFsId[pairsFsId] = ps
                    }
                }
            }

            context.saveWithErrorHandling()
            log("[Firestore] Content sync complete", level: .info)

        } catch {
            log("[Firestore] Sync failed: \(error)", level: .error)
        }
    }

    // MARK: - Parse Pair from Firestore dict

    private func parsePair(from d: [String: Any]) -> Pair? {
        guard let idStr = d["id"] as? String,
              let id = UUID(uuidString: idStr) ?? Optional(UUID())
        else { return nil }

        let displayModeRaw = d["displayMode"] as? String ?? ""
        let displayMode = DisplayMode(rawValue: displayModeRaw) ?? .parallel

        return Pair(
            id:          id,
            left:        d["left"]        as? String,
            right:       d["right"]       as? String,
            description: d["description"] as? String,
            sample:      d["sample"]      as? String,
            tag:         d["tag"]         as? String ?? "",
            leftTitle:   d["leftTitle"]   as? String,
            rightTitle:  d["rightTitle"]  as? String,
            displayMode: displayMode
        )
    }

    // MARK: - First-run stub import (offline fallback)

    /// Runs once if no developer collection exists. Provides baseline content
    /// even without network access. Safe to call every launch (guard inside).
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

    // MARK: - FSCard → Card conversion (used by importStubContent)

    /// Converts an FSCard (Firestore model) into a SwiftData Card.
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

    // MARK: - Stub implementation (offline baseline)
    // This content mirrors Phase 1 Firebase content and is replaced by
    // real Firestore data once syncFromFirestore() runs successfully.

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
