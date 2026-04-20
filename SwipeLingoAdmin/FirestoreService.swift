import Foundation
import FirebaseFirestore

// MARK: - FirestoreService
//
// Admin-side Firestore write/read service.
//
// Firestore schema:
//   /collections/{collectionId}
//       /cardSets/{setId}
//           /cards/{cardId}
//       /pairsSets/{setId}          ← items embedded as array
//
// Note: Admin-only fields (isSynced, deployStatus) are intentionally NOT
// written to Firestore — the iOS reader treats all received documents as .live.
//
// ⚠️  Requires GoogleService-Info.plist in the target and FirebaseApp.configure()
//     to have been called before first use.

struct FirestoreService {

    private var db: Firestore { Firestore.firestore() }

    // MARK: - Deploy CardSet

    /// Writes collection metadata, set metadata, and all cards to Firestore.
    /// Uses a single WriteBatch (max 500 ops). For sets with > 498 cards a
    /// FirestoreServiceError.tooManyCards error is thrown.
    func deployCardSet(
        collection: FSCollection,
        set: FSCardSet,
        cards: [FSCard]
    ) async throws {
        guard cards.count <= 498 else {
            throw FirestoreServiceError.tooManyCards(cards.count)
        }

        let batch = db.batch()
        let collRef = db.collection("collections").document(collection.id)
        let setRef  = collRef.collection("cardSets").document(set.id)

        batch.setData(collectionDoc(collection), forDocument: collRef, merge: true)
        batch.setData(cardSetDoc(set), forDocument: setRef)
        for card in cards {
            batch.setData(cardDoc(card), forDocument: setRef.collection("cards").document(card.id))
        }

        try await batch.commit()
        log("[Firestore] Deployed CardSet '\(set.name)' (\(cards.count) cards)", level: .info)
    }

    // MARK: - Deploy PairsSet

    /// Writes collection metadata + pairsSet document (items embedded) to Firestore.
    func deployPairsSet(
        collection: FSCollection,
        set: FSPairsSet
    ) async throws {
        let batch = db.batch()
        let collRef = db.collection("collections").document(collection.id)
        let setRef  = collRef.collection("pairsSets").document(set.id)

        batch.setData(collectionDoc(collection), forDocument: collRef, merge: true)
        batch.setData(pairsSetDoc(set), forDocument: setRef)

        try await batch.commit()
        log("[Firestore] Deployed PairsSet '\(set.title ?? set.id)' (\(set.items.count) pairs)", level: .info)
    }

    // MARK: - Read (for iOS app sync)

    func fetchCollectionIds() async throws -> [String] {
        let snap = try await db.collection("collections").getDocuments()
        return snap.documents.map(\.documentID)
    }

    func fetchCollection(id: String) async throws -> [String: Any] {
        let snap = try await db.collection("collections").document(id).getDocument()
        return snap.data() ?? [:]
    }

    func fetchCardSets(collectionId: String) async throws -> [[String: Any]] {
        let snap = try await db
            .collection("collections").document(collectionId)
            .collection("cardSets").getDocuments()
        return snap.documents.map { $0.data() }
    }

    func fetchCards(collectionId: String, setId: String) async throws -> [[String: Any]] {
        let snap = try await db
            .collection("collections").document(collectionId)
            .collection("cardSets").document(setId)
            .collection("cards").getDocuments()
        return snap.documents.map { $0.data() }
    }

    func fetchPairsSets(collectionId: String) async throws -> [[String: Any]] {
        let snap = try await db
            .collection("collections").document(collectionId)
            .collection("pairsSets").getDocuments()
        return snap.documents.map { $0.data() }
    }

    // MARK: - Document builders

    private func collectionDoc(_ c: FSCollection) -> [String: Any] {
        var d: [String: Any] = [
            "id":        c.id,
            "name":      c.name,
            "type":      c.type.rawValue,
            "updatedAt": Timestamp(date: c.updatedAt),
            "createdAt": Timestamp(date: c.createdAt)
        ]
        if let icon = c.icon { d["icon"] = icon }
        return d
    }

    private func cardSetDoc(_ s: FSCardSet) -> [String: Any] {
        var d: [String: Any] = [
            "id":           s.id,
            "collectionId": s.collectionId,
            "name":         s.name,
            "cefrLevel":    s.cefrLevel.rawValue,
            "accessTier":   s.accessTier.rawValue,
            "updatedAt":    Timestamp(date: s.updatedAt),
            "createdAt":    Timestamp(date: s.createdAt)
        ]
        if let desc = s.description { d["description"] = desc }
        return d
    }

    private func cardDoc(_ card: FSCard) -> [String: Any] {
        [
            "id":                 card.id,
            "setId":              card.setId,
            "en":                 card.en,
            "transcription":      card.transcription,
            "translations":       card.translations,
            "sampleEN":           card.sampleEN,
            "sampleTranslations": card.sampleTranslations,
            "tag":                card.tag,
            "updatedAt":          Timestamp(date: card.updatedAt),
            "createdAt":          Timestamp(date: card.createdAt)
        ]
    }

    private func pairsSetDoc(_ s: FSPairsSet) -> [String: Any] {
        var d: [String: Any] = [
            "id":           s.id,
            "collectionId": s.collectionId,
            "cefrLevel":    s.cefrLevel.rawValue,
            "accessTier":   s.accessTier.rawValue,
            "items":        s.items.map { pairDoc($0) },
            "updatedAt":    Timestamp(date: s.updatedAt),
            "createdAt":    Timestamp(date: s.createdAt)
        ]
        if let title = s.title       { d["title"]       = title }
        if let desc  = s.description { d["description"] = desc  }
        return d
    }

    private func pairDoc(_ p: FSPair) -> [String: Any] {
        var d: [String: Any] = [
            "id":          p.id,
            "tag":         p.tag,
            "displayMode": p.displayMode.rawValue
        ]
        if let v = p.left        { d["left"]        = v }
        if let v = p.right       { d["right"]       = v }
        if let v = p.description { d["description"] = v }
        if let v = p.sample      { d["sample"]      = v }
        if let v = p.leftTitle   { d["leftTitle"]   = v }
        if let v = p.rightTitle  { d["rightTitle"]  = v }
        return d
    }
}

// MARK: - FirestoreServiceError

enum FirestoreServiceError: LocalizedError {
    case tooManyCards(Int)

    var errorDescription: String? {
        switch self {
        case .tooManyCards(let count):
            return "Too many cards (\(count)) for a single deploy batch. Max 498 cards per set."
        }
    }
}
