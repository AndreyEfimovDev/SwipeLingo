import Foundation
import FirebaseFirestore

/// Узкий протокол над `Firestore.firestore()` — по тому же принципу, что `AuthClient`
/// над `Auth.auth()`. Абстрагируется только точка входа синглтона: `CollectionReference`,
/// `DocumentReference`, `Query` и т.д. дальше по цепочке остаются конкретными типами
/// Firebase SDK — их дальнейшее API уже не завязано напрямую на `Firestore.firestore()`.
protocol FirestoreClient {
    func collection(_ collectionPath: String) -> CollectionReference
}

extension Firestore: FirestoreClient {}
