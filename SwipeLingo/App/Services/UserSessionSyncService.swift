import Foundation
import SwiftData
import FirebaseAuth

// MARK: - UserSessionSyncService
//
// Синхронизация после подтверждённого входа (isSessionVerified): локальный
// UserProfile (SwiftData) + удалённый документ пользователя в Firestore.
// Вынесен из SwipeLingoApp — это бизнес-логика синхронизации, а не забота
// точки входа. appSyncStateService (флаг онбординга) сюда не передаётся —
// сервис только сообщает "returning user?", решение о флаге остаётся у
// вызывающей стороны (composition root), чтобы сервис не держал ссылку на
// чужое @State.

struct UserSessionSyncService {

    /// Синхронизирует локальный `UserProfile` и удалённый документ пользователя
    /// после подтверждённого входа. Создаёт профиль, если его ещё нет; сбрасывает
    /// его, если UID сменился (другой пользователь вошёл на этом устройстве);
    /// проставляет UID и имя из Firebase; затем синхронизирует профиль и подписку
    /// с Firestore.
    /// - Returns: `true`, если это "возвращающийся" пользователь — в документе
    ///   Firestore уже был сохранён `cefrLevel` (второе устройство). Вызывающая
    ///   сторона использует это, чтобы пропустить онбординг.
    @discardableResult
    func syncAfterVerifiedSession(
        user: FirebaseAuth.User,
        container: ModelContainer?,
        nativeLanguage: NativeLanguage,
        userService: UserFBService
    ) async -> Bool {
        let ctx = container?.mainContext
        let profiles = ctx?.fetchWithErrorHandling(FetchDescriptor<UserProfile>()) ?? []
        var profile = profiles.first

        if profile == nil {
            let p = UserProfile()
            ctx?.insert(p)
            profile = p
        }

        // Несовпадение UID → вошёл другой пользователь, сбрасываем профиль.
        if let p = profile, !p.firebaseUID.isEmpty, p.firebaseUID != user.uid {
            log("Firebase UID changed — resetting UserProfile", level: .info)
            p.name = ""
            p.cefrLevel = .a1
        }

        // Проставляем UID и синхронизируем имя из Firebase.
        profile?.firebaseUID = user.uid
        if user.isAnonymous {
            if profile?.name.isEmpty == true { profile?.name = "Anonymous" }
        } else if let n = user.displayName, !n.isEmpty {
            profile?.name = n
        } else if let email = user.email, !email.isEmpty {
            profile?.name = String(email.prefix(while: { $0 != "@" }))
        }
        ctx?.saveWithErrorHandling()

        let cefrRaw = profile?.cefrLevel.rawValue ?? ""
        let isReturningUser = await userService.createOrUpdateUser(user, nativeLanguage: nativeLanguage.rawValue, cefrLevel: cefrRaw)
        await userService.syncSubscription(for: user.uid)
        return isReturningUser
    }
}
