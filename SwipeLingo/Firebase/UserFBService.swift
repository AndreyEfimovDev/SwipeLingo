import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// MARK: - UserFBService
//
// Управляет документом пользователя в Firestore (users/{uid}) и локальным кэшем подписки.
//
// Обязанности:
//  • createOrUpdateUser — upsert при первом входе / привязке провайдера
//  • syncSubscription   — получает подписку из Firestore и обновляет локальный кэш
//  • effectivePlan      — определение плана офлайн-safe способом, с учётом grace period
//
// Логика подписки:
//  • Free → Paid : 30-дневный Pro-триал (Constants.trialDurationDays), status=trial, без grace period
//  • Paid → Paid : прямая активация, status=active, endDate=сейчас+1год
//  • Paid → Free : отмена — status=cancelled, plan+endDate не меняются, действует grace period
//
// Ключи локального кэша → Constants.StorageKey
// Grace period: Constants.subscriptionGracePeriodDays дней (только для платных, не для триала).

@Observable
@MainActor
final class UserFBService {

    private(set) var isLoading = false

    /// Абстракция над `Firestore.firestore()` — см. `FirestoreClient` для причины (тестируемость).
    /// По умолчанию — настоящий `Firestore.firestore()`, в тестах подставляется fake.
    private let db: FirestoreClient

    // MARK: - Кэш подписки (@Observable)
    //
    // Персистентный кэш последнего известного состояния подписки — единственный
    // источник правды для всего приложения вместо параллельных @AppStorage-читателей
    // по разным экранам. Пишут сюда только методы этого класса (cachePlan/cachePending/
    // clearPending) — они же зеркалят значения в UserDefaults для персистентности между
    // запусками (init читает их обратно). Использовать effectivePlan() там, где нужен
    // план с учётом grace period, userPlan — когда нужно "как есть".

    private(set) var userPlan: AccessTier
    private(set) var subscriptionStatus: SubscriptionStatus
    private(set) var billingCycle: BillingCycle
    private(set) var planExpiry: Date?
    private(set) var pendingPlan: AccessTier?
    private(set) var pendingBillingCycle: BillingCycle

    init(db: FirestoreClient = Firestore.firestore()) {
        self.db = db

        let planRaw = UserDefaults.standard.string(forKey: Constants.StorageKey.userPlan) ?? AccessTier.free.rawValue
        userPlan = AccessTier(rawValue: planRaw) ?? .free

        let statusRaw = UserDefaults.standard.string(forKey: Constants.StorageKey.cachedPlanStatus) ?? SubscriptionStatus.active.rawValue
        subscriptionStatus = SubscriptionStatus(rawValue: statusRaw) ?? .active

        let cycleRaw = UserDefaults.standard.string(forKey: Constants.StorageKey.cachedBillingCycle) ?? BillingCycle.none.rawValue
        billingCycle = BillingCycle(rawValue: cycleRaw) ?? .none

        let expiryTS = UserDefaults.standard.double(forKey: Constants.StorageKey.cachedPlanExpiry)
        planExpiry = expiryTS > 0 ? Date(timeIntervalSince1970: expiryTS) : nil

        let pendingPlanRaw = UserDefaults.standard.string(forKey: Constants.StorageKey.cachedPendingPlan) ?? ""
        pendingPlan = AccessTier(rawValue: pendingPlanRaw)

        let pendingCycleRaw = UserDefaults.standard.string(forKey: Constants.StorageKey.cachedPendingCycle) ?? BillingCycle.none.rawValue
        pendingBillingCycle = BillingCycle(rawValue: pendingCycleRaw) ?? .none
    }

    // MARK: - Upsert user document

    /// Создаёт документ пользователя в Firestore при первом входе.
    /// При повторных входах обновляет provider + displayName + updatedAt всегда, и
    /// nativeLanguage/cefrLevel — если переданы непустыми (подписка не трогается).
    /// Единственная функция, которая пишет `cefrLevel` в Firestore — вызывать явно
    /// при каждом реальном изменении уровня (не только при логине), иначе поле
    /// останется таким, каким было при создании документа (баг, найденный в сентябре
    /// 2026: `ProfileView.saveChanges()` менял уровень только локально).
    /// Возвращает `true`, если документ пользователя уже существовал с установленным cefrLevel —
    /// используется SwipeLingoApp, чтобы пропустить онбординг на втором устройстве (возвращающийся пользователь).
    @discardableResult
    func createOrUpdateUser(
        _ firebaseUser: FirebaseAuth.User,
        nativeLanguage: String = "",
        cefrLevel: String = ""
    ) async -> Bool {
        let ref = db.collection("users").document(firebaseUser.uid)
        do {
            let snapshot = try await ref.getDocument()
            if snapshot.exists {
                let isReturningUser = (snapshot.data()?["cefrLevel"] as? String)?.isEmpty == false
                // Обновляем только изменяемые поля — НЕ перезаписываем subscription.
                // nativeLanguage backfill'ит аккаунты, созданные до того, как онбординг стал задавать настройку.
                var updates: [String: Any] = [
                    "authProvider": AuthProviderID.from(firebaseUser),
                    "displayName":  firebaseUser.displayName ?? "",
                    "email":        firebaseUser.isAnonymous ? NSNull() : (firebaseUser.email as Any),
                    "updatedAt":    Timestamp(date: Date())
                ]
                if !nativeLanguage.isEmpty { updates["nativeLanguage"] = nativeLanguage }
                if !cefrLevel.isEmpty { updates["cefrLevel"] = cefrLevel }
                try await ref.updateData(updates)
                log("User document updated: \(firebaseUser.uid) returningUser:\(isReturningUser)", level: .info)
                return isReturningUser
            } else {
                // Первый вход — создаём полный документ
                let doc = UserFSDocument.make(
                    from: firebaseUser,
                    nativeLanguage: nativeLanguage,
                    cefrLevel: cefrLevel
                )
                try ref.setData(from: doc)
                log("User document created: \(firebaseUser.uid)", level: .info)
                // Кэшируем план Free по умолчанию
                cachePlan(.free, status: .active, expiry: nil)
                return false
            }
        } catch {
            log("createOrUpdateUser failed: \(error)", level: .error)
            return false
        }
    }

    // MARK: - Sync subscription

    /// Получает подписку из Firestore и обновляет локальный кэш AppStorage.
    /// Вызывать при запуске приложения (когда есть сеть) и после изменений плана.
    /// Сразу после записи вызывает effectivePlan() — grace-period self-healing
    /// (даунгрейд в .free при истёкшей подписке) применяется к кэшу немедленно.
    func syncSubscription(for uid: String) async {
        guard FirebaseApp.app() != nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db.collection("users").document(uid).getDocument()
            guard snapshot.exists,
                  let doc = try? snapshot.data(as: UserFSDocument.self)
            else { return }

            let sub          = doc.subscription
            let plan         = AccessTier(rawValue: sub.plan)          ?? .free
            let status       = SubscriptionStatus(rawValue: sub.status) ?? .active
            let billingCycle = BillingCycle(rawValue: sub.billingCycle) ?? .none
            // Триал использует trialEndDate как срок истечения; платная — endDate
            let expiry = status == .trial ? sub.trialEndDate : sub.endDate

            cachePlan(plan, status: status, expiry: expiry, billingCycle: billingCycle)

            if let pendingRaw = sub.pendingPlan, let pendingPlan = AccessTier(rawValue: pendingRaw) {
                let pendingCycle = sub.pendingBillingCycle.flatMap { BillingCycle(rawValue: $0) } ?? .none
                cachePending(plan: pendingPlan, billingCycle: pendingCycle)
            } else {
                clearPending()
            }

            // Триггерим grace-period self-healing сразу после свежей записи кэша: если сервер
            // прислал уже истёкшую (по grace period) подписку — effectivePlan() тут же откатит
            // кэш в .free. Без этого вызова вся grace-period-логика в effectivePlan() мертва —
            // никто её не вызывал, и просроченные Pro/Go продолжали бы читаться из @AppStorage(userPlan)
            // во всех экранах, которые читают его напрямую (SettingsView, CardsView, BooksView и т.д.).
            _ = effectivePlan()

            log("Subscription synced: \(plan.rawValue) / \(status.rawValue)", level: .info)

        } catch {
            log("syncSubscription failed: \(error)", level: .error)
        }
    }

    // MARK: - Effective plan (offline-safe)

    /// Определяет текущий план пользователя из локального кэша, с учётом grace period.
    /// - Если закэшированный план истёк и grace period прошёл → возвращает .free
    /// - Иначе возвращает закэшированный план (работает офлайн)
    func effectivePlan() -> AccessTier {
        guard userPlan != .free else { return .free }

        let isTrial = subscriptionStatus == .trial

        guard let expiry = planExpiry else { return userPlan } // нет срока истечения → подписка активна бессрочно

        if isTrial {
            // Триал: жёсткая граница на trialEndDate, без grace period
            if Date() > expiry {
                cachePlan(.free, status: .expired, expiry: nil)
                log("Trial expired → downgraded to Free", level: .info)
                return .free
            }
            return userPlan
        }

        // Платная подписка: применяем grace period
        let graceCutoff = expiry.addingTimeInterval(
            Double(Constants.subscriptionGracePeriodDays) * 86_400
        )
        if Date() > graceCutoff {
            cachePlan(.free, status: .expired, expiry: nil)
            log("Subscription expired + grace period over → downgraded to Free", level: .info)
            return .free
        }
        if Date() > expiry {
            log("Subscription expired, grace period active (\(Constants.subscriptionGracePeriodDays)d remaining)", level: .info)
        }
        return userPlan
    }

    // MARK: - Update subscription

    /// Симулированная покупка: активирует подписку, пишет PaymentRecord + PlanHistoryRecord в Firestore.
    /// cardLast4 — последние 4 цифры фейковой карты.
    @discardableResult
    func purchaseSubscription(
        plan: AccessTier,
        billingCycle: BillingCycle,
        amount: Double,
        cardLast4: String,
        currency: String = "USD",
        for uid: String
    ) async -> Bool {
        let currentPlan = userPlan

        let now      = Date()
        let days: Double = billingCycle == .monthly ? 30 : 365
        let endDate  = now.addingTimeInterval(days * 86_400)

        let ref = db.collection("users").document(uid)

        let subscriptionUpdate: [String: Any] = [
            "subscription.plan":                plan.rawValue,
            "subscription.billingCycle":        billingCycle.rawValue,
            "subscription.status":              SubscriptionStatus.active.rawValue,
            "subscription.startDate":           Timestamp(date: now),
            "subscription.endDate":             Timestamp(date: endDate),
            "subscription.trialEndDate":        NSNull(),
            "subscription.amount":              amount,
            "subscription.currency":            currency,
            "subscription.pendingPlan":         NSNull(),
            "subscription.pendingBillingCycle": NSNull(),
            "updatedAt":                        Timestamp(date: now)
        ]

        let reason: String
        if currentPlan == .free      { reason = "upgrade" }
        else if plan.rank > currentPlan.rank { reason = "upgrade" }
        else if plan.rank < currentPlan.rank { reason = "downgrade" }
        else                         { reason = "cycle_change" }

        let paymentId = UUID().uuidString
        let payment   = PaymentRecord(
            id: paymentId, date: now, amount: amount, currency: currency,
            plan: plan.rawValue, billingCycle: billingCycle.rawValue,
            paymentMethod: "card", last4: cardLast4,
            status: PaymentStatus.success.rawValue
        )

        let historyId = UUID().uuidString
        let history   = PlanHistoryRecord(
            id: historyId, date: now,
            fromPlan: currentPlan.rawValue, toPlan: plan.rawValue, reason: reason
        )

        do {
            try await ref.updateData(subscriptionUpdate)
            try ref.collection("paymentHistory").document(paymentId).setData(from: payment)
            try ref.collection("planHistory").document(historyId).setData(from: history)
            cachePlan(plan, status: .active, expiry: endDate, billingCycle: billingCycle)
            clearPending()
            log("Subscription purchased: \(plan.rawValue)/\(billingCycle.rawValue)", level: .info)
            return true
        } catch {
            log("purchaseSubscription failed: \(error)", level: .error)
            return false
        }
    }

    /// Загружает историю платежей из Firestore, сортировка от новых к старым.
    func loadPaymentHistory(for uid: String) async -> [PaymentRecord] {
        do {
            let snap = try await db.collection("users").document(uid)
                .collection("paymentHistory")
                .order(by: "date", descending: true)
                .getDocuments()
            return snap.documents.compactMap { try? $0.data(as: PaymentRecord.self) }
        } catch {
            log("loadPaymentHistory failed: \(error)", level: .error)
            return []
        }
    }

    /// Планирует понижение плана — текущий план остаётся активным до endDate, pending устанавливается на новый план/цикл.
    func scheduleDowngrade(plan: AccessTier, billingCycle: BillingCycle, for uid: String) async {
        let data: [String: Any] = [
            "subscription.pendingPlan":         plan.rawValue,
            "subscription.pendingBillingCycle": billingCycle.rawValue,
            "updatedAt":                        Timestamp(date: Date())
        ]
        do {
            try await db.collection("users").document(uid).updateData(data)
            cachePending(plan: plan, billingCycle: billingCycle)
            log("Downgrade scheduled → \(plan.rawValue)/\(billingCycle.rawValue)", level: .info)
        } catch {
            log("scheduleDowngrade failed: \(error)", level: .error)
        }
    }

    /// Отменяет подписку — доступ сохраняется до endDate, статус меняется на cancelled.
    func cancelSubscription(for uid: String) async {
        await cancelSubscription(for: uid, currentPlan: userPlan)
    }

    @discardableResult
    func updateSubscription(plan: AccessTier, for uid: String) async -> Bool {
        let currentPlan = userPlan

        if plan == .free && currentPlan != .free {
            await cancelSubscription(for: uid, currentPlan: currentPlan)
        } else if plan != .free && currentPlan == .free {
            return await startTrial(pendingPlan: plan, for: uid)
        } else if plan != .free && currentPlan != .free {
            await activateSubscription(plan: plan, for: uid)
        }
        return true
    }

    // Триал всегда даёт доступ Pro, чтобы показать полный набор фич.
    // pendingPlan фиксирует, за что пользователь планирует платить после триала.
    // Возвращает false, если триал уже был использован (trialEndDate есть в Firestore).
    func startTrial(pendingPlan: AccessTier, for uid: String) async -> Bool {
        let ref = db.collection("users").document(uid)
        do {
            let snapshot = try await ref.getDocument()
            if let doc = try? snapshot.data(as: UserFSDocument.self),
               doc.subscription.trialEndDate != nil {
                log("startTrial blocked — trial already used for \(uid)", level: .info)
                return false
            }

            let now      = Date()
            let trialEnd = now.addingTimeInterval(Double(Constants.trialDurationDays) * 86_400)

            let data: [String: Any] = [
                "subscription.plan":               AccessTier.pro.rawValue,
                "subscription.billingCycle":       BillingCycle.none.rawValue,
                "subscription.status":             SubscriptionStatus.trial.rawValue,
                "subscription.startDate":          Timestamp(date: now),
                "subscription.endDate":            NSNull(),
                "subscription.trialEndDate":       Timestamp(date: trialEnd),
                "subscription.pendingPlan":        pendingPlan.rawValue,
                "subscription.pendingBillingCycle": BillingCycle.yearly.rawValue,
                "updatedAt":                       Timestamp(date: now)
            ]
            try await ref.updateData(data)
            cachePlan(.pro, status: .trial, expiry: trialEnd)
            log("Trial started → Pro until \(trialEnd), pending: \(pendingPlan.rawValue)", level: .info)
            return true
        } catch {
            log("startTrial failed: \(error)", level: .error)
            return false
        }
    }

    private func activateSubscription(plan: AccessTier, for uid: String) async {
        let now     = Date()
        let endDate = now.addingTimeInterval(365 * 86_400)

        let data: [String: Any] = [
            "subscription.plan":               plan.rawValue,
            "subscription.billingCycle":       BillingCycle.yearly.rawValue,
            "subscription.status":             SubscriptionStatus.active.rawValue,
            "subscription.startDate":          Timestamp(date: now),
            "subscription.endDate":            Timestamp(date: endDate),
            "subscription.trialEndDate":       NSNull(),
            "subscription.pendingPlan":        NSNull(),
            "subscription.pendingBillingCycle": NSNull(),
            "updatedAt":                       Timestamp(date: now)
        ]
        do {
            try await db.collection("users").document(uid).updateData(data)
            cachePlan(plan, status: .active, expiry: endDate)
            log("Subscription activated → \(plan.rawValue)", level: .info)
        } catch {
            log("activateSubscription failed: \(error)", level: .error)
        }
    }

    func cancelSubscription(for uid: String, currentPlan: AccessTier) async {
        // Оставляем plan + endDate без изменений — пользователь сохраняет доступ до истечения срока.
        // Обновляем только status и pendingPlan.
        let data: [String: Any] = [
            "subscription.status":            SubscriptionStatus.cancelled.rawValue,
            "subscription.pendingPlan":       AccessTier.free.rawValue,
            "subscription.pendingBillingCycle": BillingCycle.none.rawValue,
            "updatedAt":                      Timestamp(date: Date())
        ]
        do {
            try await db.collection("users").document(uid).updateData(data)
            // Оставляем текущий план в локальном кэше, обновляем только status
            let expiry = planExpiry
            cachePlan(currentPlan, status: .cancelled, expiry: expiry)
            cachePending(plan: .free, billingCycle: .none)
            log("Subscription cancelled — access until \(expiry?.description ?? "unknown")", level: .info)
        } catch {
            log("cancelSubscription failed: \(error)", level: .error)
        }
    }

    // MARK: - Update notification email

    func updateNotificationEmail(_ email: String, for uid: String) async {
        do {
            try await db.collection("users").document(uid).updateData([
                "notificationEmail": email.isEmpty ? NSNull() : email,
                "updatedAt":         Timestamp(date: Date())
            ])
            log("Notification email updated", level: .info)
        } catch {
            log("updateNotificationEmail failed: \(error)", level: .error)
        }
    }

    // MARK: - Local cache

    private func cachePending(plan: AccessTier, billingCycle: BillingCycle) {
        pendingPlan = plan
        pendingBillingCycle = billingCycle
        UserDefaults.standard.set(plan.rawValue,         forKey: Constants.StorageKey.cachedPendingPlan)
        UserDefaults.standard.set(billingCycle.rawValue, forKey: Constants.StorageKey.cachedPendingCycle)
    }

    private func clearPending() {
        pendingPlan = nil
        pendingBillingCycle = .none
        UserDefaults.standard.removeObject(forKey: Constants.StorageKey.cachedPendingPlan)
        UserDefaults.standard.removeObject(forKey: Constants.StorageKey.cachedPendingCycle)
    }

    private func cachePlan(_ plan: AccessTier, status: SubscriptionStatus, expiry: Date?, billingCycle: BillingCycle = .none) {
        userPlan = plan
        subscriptionStatus = status
        self.billingCycle = billingCycle
        planExpiry = expiry

        UserDefaults.standard.set(plan.rawValue,          forKey: Constants.StorageKey.userPlan)
        UserDefaults.standard.set(status.rawValue,        forKey: Constants.StorageKey.cachedPlanStatus)
        UserDefaults.standard.set(billingCycle.rawValue,  forKey: Constants.StorageKey.cachedBillingCycle)
        if let expiry {
            UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: Constants.StorageKey.cachedPlanExpiry)
        } else {
            UserDefaults.standard.removeObject(forKey: Constants.StorageKey.cachedPlanExpiry)
        }
    }
}
