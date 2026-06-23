import SwiftUI
import SwiftData
import FirebaseAuth
import AuthenticationServices

// MARK: - ProfileView
// User profile: name, auth state, subscription plan, English level.

struct ProfileView: View {

    @AppStorage(Constants.StorageKey.userPlan)           private var userPlan:      AccessTier    = .free
    @AppStorage(Constants.StorageKey.cachedPlanStatus)   private var planStatus:    String        = SubscriptionStatus.active.rawValue
    @AppStorage(Constants.StorageKey.cachedBillingCycle) private var planCycle:     String        = BillingCycle.none.rawValue
    @AppStorage(Constants.StorageKey.cachedPendingPlan)  private var pendingPlanRaw: String       = ""
    @AppStorage(Constants.StorageKey.cachedPendingCycle) private var pendingCycleRaw: String      = ""
    @AppStorage(Constants.StorageKey.nativeLanguage)     private var nativeLanguage: NativeLanguage = .russian
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self)  private var authService
    @Environment(UserService.self)  private var userService

    @AppStorage("appleRelayBannerDismissed") private var relayBannerDismissed = false

    @State private var nameInput  = ""
    @State private var pendingLevel: CEFRLevel = .a1
    @State private var isInitialized     = false
    @State private var saveConfirmed     = false
    @State private var showAuth          = false
    @State private var showPlans         = false
    @State private var didCopyUID        = false
    @State private var showDeleteConfirm         = false
    @State private var needsAppleReauthForDeletion = false
    @State private var isDeletingAccount         = false
    @State private var deleteErrorMessage: String? = nil
    @State private var isResendingVerification = false
    @State private var verificationSent    = false

    private var profile: UserProfile? { profiles.first }
    private var isAppleRelayEmail: Bool {
        authService.currentUser?.email?.contains("privaterelay.appleid.com") == true
    }
    private var linkedProviders: [String] {
        authService.currentUser?.providerData.map { $0.providerID } ?? []
    }
    private var hasChanges: Bool {
        guard isInitialized, let profile else { return false }
        return nameInput != profile.name || pendingLevel != profile.cefrLevel
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                nameSection
                emailVerificationBanner
                appleRelayBanner
                accountSection
                levelSection
                languageSection
            }
            .padding(.vertical, 16)
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .customBackButton("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if saveConfirmed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.myColors.myGreen)
                        .transition(.scale.combined(with: .opacity))
                } else if hasChanges {
                    Button("Save") { saveChanges() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.myColors.myBlue)
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            if profiles.isEmpty { context.insert(UserProfile()) }
            nameInput    = profile?.name ?? ""
            pendingLevel = profile?.cefrLevel ?? .a1
            isInitialized = true
            Task { await authService.reloadUser() }
        }
        .sheet(isPresented: $showAuth) {
            AuthView(isDismissible: true)
                .environment(authService)
                .onChange(of: authService.isAnonymous) { _, isAnon in
                    if !isAnon { showAuth = false }
                }
        }
        .sheet(isPresented: $showPlans) {
            PlansView()
        }
        .alert("Delete Account", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if authService.isAppleUser {
                    needsAppleReauthForDeletion = true
                } else {
                    Task { await deleteAccount() }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your account and all associated data will be permanently deleted. This cannot be undone.")
        }
        .sheet(isPresented: $needsAppleReauthForDeletion) {
            AppleDeletionSheet { authorization in
                needsAppleReauthForDeletion = false
                Task { await deleteAccountWithApple(authorization) }
            }
            .environment(authService)
        }
        .alert("Cannot Delete Account", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    // MARK: - Email Verification Banner

    @ViewBuilder
    private var emailVerificationBanner: some View {
        let user = authService.currentUser
        let needsVerification = !(user?.isAnonymous ?? true)
            && !(user?.isEmailVerified ?? true)
            && user?.email != nil

        if needsVerification {
            HStack(spacing: 12) {
                Image(systemName: "envelope.badge")
                    .font(.title3)
                    .foregroundStyle(Color.myColors.myOrange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Verify your email")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.myColors.myAccent)
                    Text(user?.email ?? "")
                        .font(.caption)
                        .foregroundStyle(Color.myColors.mySecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    Task { await resendVerification() }
                } label: {
                    if isResendingVerification {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.myColors.myBlue)
                            .frame(width: 44)
                    } else {
                        Text(verificationSent ? "Sent ✓" : "Resend")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(verificationSent
                                ? Color.myColors.myGreen
                                : Color.myColors.myBlue)
                            .frame(width: 44)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isResendingVerification || verificationSent)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(Color.myColors.myOrange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.myColors.myOrange.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Apple Relay Banner

    @ViewBuilder
    private var appleRelayBanner: some View {
        if !relayBannerDismissed && isAppleRelayEmail {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(Color.myColors.myBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Signed in with Apple")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.myColors.myAccent)
                    Text("Apple hides your real email. Always use Sign in with Apple on new devices to access your data.")
                        .font(.caption)
                        .foregroundStyle(Color.myColors.mySecondary)
                }

                Spacer()

                Button {
                    withAnimation { relayBannerDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.myColors.mySecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.myColors.myBlue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.myColors.myBlue.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NAME")
                .font(.caption)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle")
                        .font(.title2)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.4))

                    TextField("Anonymous", text: $nameInput)
                        .font(.body)
                        .foregroundStyle(Color.myColors.myAccent)
                        .submitLabel(.done)
                }
                .frame(height: 52)
                .padding(.horizontal, 16)

                if let uid = authService.currentUser?.uid {
                    Divider().padding(.leading, 56)

                    HStack(spacing: 8) {
                        Text("ID: \(uid)")
                            .font(.caption2)
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.35))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = uid
                            withAnimation { didCopyUID = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { didCopyUID = false }
                            }
                        } label: {
                            Image(systemName: didCopyUID ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(didCopyUID ? Color.myColors.myGreen : Color.myColors.myAccent.opacity(0.4))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                }
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACCOUNT")
                .font(.caption)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                if authService.isAnonymous {
                    Button { showAuth = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.title2)
                                .foregroundStyle(Color.myColors.myBlue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sign In / Create Account")
                                    .font(.body)
                                    .foregroundStyle(Color.myColors.myBlue)
                                Text("Guest — progress not saved")
                                    .font(.caption)
                                    .foregroundStyle(Color.myColors.mySecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                        }
                        .frame(minHeight: 52)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.myColors.myBlue)
                        Text(authService.currentUser?.email
                             ?? authService.currentUser?.displayName
                             ?? "Account")
                            .font(.body)
                            .foregroundStyle(Color.myColors.myAccent)
                        if let user = authService.currentUser,
                           user.providerData.contains(where: { $0.providerID == "password" }) {
                            Image(systemName: user.isEmailVerified ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(user.isEmailVerified ? Color.myColors.myGreen : Color.myColors.myOrange)
                        }
                        Spacer()
                    }
                    .frame(height: 52)
                    .padding(.horizontal, 16)

                    if !linkedProviders.isEmpty {
                        Divider().padding(.leading, 56)
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .font(.body)
                                .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                            Text("Linked with")
                                .font(.subheadline)
                                .foregroundStyle(Color.myColors.mySecondary)
                            Spacer()
                            HStack(spacing: 6) {
                                ForEach(linkedProviders, id: \.self) { providerID in
                                    providerChip(providerID)
                                }
                            }
                        }
                        .frame(height: 44)
                        .padding(.horizontal, 16)
                    }

                    Divider().padding(.leading, 56)

                    Button {
                        try? authService.signOut()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.title2)
                                .foregroundStyle(Color.myColors.myRed)
                            Text("Sign Out")
                                .font(.body)
                                .foregroundStyle(Color.myColors.myRed)
                            Spacer()
                        }
                        .frame(height: 52)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 56)

                    Button { showDeleteConfirm = true } label: {
                        HStack(spacing: 12) {
                            if isDeletingAccount {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "person.crop.circle.badge.minus")
                                    .font(.title2)
                                    .foregroundStyle(Color.myColors.myRed.opacity(0.7))
                            }
                            Text("Delete Account")
                                .font(.body)
                                .foregroundStyle(Color.myColors.myRed.opacity(0.7))
                            Spacer()
                        }
                        .frame(height: 52)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeletingAccount)
                }
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Plan

    private var subscriptionStatus: SubscriptionStatus {
        SubscriptionStatus(rawValue: planStatus) ?? .active
    }

    private var subscriptionCycle: BillingCycle {
        BillingCycle(rawValue: planCycle) ?? .none
    }

    private var cachedExpiry: Date? {
        let ts = UserDefaults.standard.double(forKey: Constants.StorageKey.cachedPlanExpiry)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    private var pendingPlan: AccessTier? {
        guard !pendingPlanRaw.isEmpty else { return nil }
        let plan = AccessTier(rawValue: pendingPlanRaw) ?? .free
        // Only meaningful if it differs from current plan or cycle
        let pendingCycle = BillingCycle(rawValue: pendingCycleRaw) ?? .none
        if plan == userPlan && pendingCycle == subscriptionCycle { return nil }
        return plan
    }

    private var pendingCycle: BillingCycle {
        BillingCycle(rawValue: pendingCycleRaw) ?? .none
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PLAN")
                .font(.caption)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                // Plan + cycle row
                HStack(spacing: 10) {
                    AccessTierBadge(tier: userPlan)
                    if userPlan != .free && subscriptionCycle != .none {
                        Text(subscriptionCycle.displayName)
                            .font(.body)
                            .foregroundStyle(Color.myColors.myAccent)
                    } else if userPlan == .free {
                        Text(userPlan.displayName)
                            .font(.body)
                            .foregroundStyle(Color.myColors.myAccent)
                    }
                    Spacer()
                }
                .frame(height: 52)
                .padding(.horizontal, 16)

                // Status row (expiry / next billing) — only for paid plans
                if userPlan != .free, let expiry = cachedExpiry {
                    Divider().padding(.leading, 16)
                    HStack(spacing: 10) {
                        let hasPending = pendingPlan != nil
                        let isCancelled = subscriptionStatus == .cancelled
                        Image(systemName: isCancelled || hasPending ? "arrow.triangle.2.circlepath" : "arrow.clockwise.circle")
                            .font(.title3)
                            .foregroundStyle(isCancelled || hasPending
                                ? Color.myColors.myOrange
                                : Color.myColors.mySecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            if let pending = pendingPlan {
                                let pCycle = pendingCycle
                                let isCancellingToFree = pending == .free
                                HStack(spacing: 4) {
                                    Text(isCancellingToFree ? "Cancels" : "Changes to")
                                        .font(.caption)
                                        .foregroundStyle(Color.myColors.myOrange)
                                    if !isCancellingToFree {
                                        AccessTierBadge(tier: pending)
                                        if pCycle != .none {
                                            Text(pCycle.displayName)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(Color.myColors.myOrange)
                                        }
                                    }
                                }
                                Text(expiry, style: .date)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.myColors.myAccent)
                            } else {
                                Text(isCancelled ? "Access until" : "Renews")
                                    .font(.caption)
                                    .foregroundStyle(Color.myColors.mySecondary)
                                Text(expiry, style: .date)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.myColors.myAccent)
                            }
                        }
                        Spacer()
                        if let pending = pendingPlan {
                            // Show new plan's price
                            let pCycle = pendingCycle == .none ? subscriptionCycle : pendingCycle
                            if pending != .free {
                                Text(String(format: "$%.2f", pending.price(for: pCycle)))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.myColors.myOrange)
                            }
                        } else if !isCancelled {
                            Text(String(format: "$%.2f", userPlan.price(for: subscriptionCycle)))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.myColors.myAccent)
                        }
                    }
                    .frame(minHeight: 52)
                    .padding(.horizontal, 16)
                }

                // MONETIZATION_STUB: кнопка Subscribe/Manage скрыта — монетизация отключена.
                // Когда будет готова: убрать эту заглушку и раскомментировать блок ниже.
                //
                // Divider().padding(.leading, 16)
                // Button { showPlans = true } label: {
                //     HStack(spacing: 12) {
                //         Image(systemName: userPlan == .free ? "star.circle" : "gearshape.circle")
                //             .font(.title2)
                //             .foregroundStyle(Color.myColors.myBlue)
                //         Text(userPlan == .free ? "Subscribe to Go or Pro" : "Manage Subscription")
                //             .font(.body)
                //             .foregroundStyle(userPlan == .free ? Color.myColors.myBlue : Color.myColors.myAccent)
                //         Spacer()
                //         Image(systemName: "chevron.right")
                //             .font(.caption.weight(.semibold))
                //             .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                //     }
                //     .frame(height: 52)
                //     .padding(.horizontal, 16)
                //     .contentShape(Rectangle())
                // }
                // .buttonStyle(.plain)

                // Payment History — only for paid/former-paid users
                if userPlan != .free || subscriptionStatus == .cancelled, let uid = authService.currentUser?.uid {
                    Divider().padding(.leading, 16)
                    NavigationLink {
                        PaymentHistoryView(uid: uid)
                            .environment(userService)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.title2)
                                .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                            Text("Payment History")
                                .font(.body)
                                .foregroundStyle(Color.myColors.myAccent)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                        }
                        .frame(height: 52)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - English Level

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ENGLISH LEVEL")
                .font(.caption)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                ForEach(Array(CEFRLevel.allCases.enumerated()), id: \.offset) { index, level in
                    if index > 0 { Divider().padding(.leading, 16) }
                    Button {
                        pendingLevel = level
                    } label: {
                        HStack(spacing: 10) {
                            Text(level.displayCode)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(level.color)
                                .frame(width: 36, alignment: .leading)
                            Text(level.displayName)
                                .foregroundStyle(Color.myColors.myAccent)
                            Spacer()
                            if pendingLevel == level {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.myColors.myBlue)
                            }
                        }
                        .font(.body)
                        .frame(height: 52)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NATIVE LANGUAGE")
                .font(.caption)
                .padding(.horizontal, 32)

            HStack {
                Text("Native language")
                Spacer()
                Text("\(nativeLanguage.flag) \(nativeLanguage.displayName)")
                    .foregroundStyle(Color.myColors.mySecondary)
            }
            .font(.body)
            .frame(height: 52)
            .padding(.horizontal, 16)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Helpers

    private func providerChip(_ providerID: String) -> some View {
        let label: String = switch providerID {
        case "password": "Email"
        case "google.com": "Google"
        case "apple.com": "Apple"
        default: providerID
        }
        return Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.myColors.myAccent.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.myColors.myAccent.opacity(0.08))
            .clipShape(Capsule())
    }

    // MARK: - Actions

    private func saveChanges() {
        let trimmedName = nameInput.trimmingCharacters(in: .whitespaces)
        let nameChanged = trimmedName != (profile?.name ?? "")
        profile?.name = trimmedName
        profile?.cefrLevel = pendingLevel
        context.saveWithErrorHandling()
        if !authService.isAnonymous && nameChanged && authService.isSessionVerified {
            Task { try? await authService.updateDisplayName(trimmedName) }
        }
        withAnimation(.spring(duration: 0.35)) { saveConfirmed = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) { saveConfirmed = false }
        }
    }

    private func resendVerification() async {
        isResendingVerification = true
        defer { isResendingVerification = false }
        do {
            try await authService.sendEmailVerification()
            withAnimation { verificationSent = true }
        } catch {
            log("[ProfileView] sendEmailVerification failed: \(error)", level: .error)
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await authService.deleteAccount()
        } catch let error as NSError {
            log("[ProfileView] deleteAccount failed: \(error)", level: .error)
            if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                deleteErrorMessage = "For security, please sign out and sign in again before deleting your account."
            } else {
                deleteErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteAccountWithApple(_ authorization: ASAuthorization) async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await authService.deleteAccountWithApple(authorization: authorization)
        } catch let error as NSError {
            log("[ProfileView] deleteAccountWithApple failed: \(error)", level: .error)
            if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                deleteErrorMessage = "For security, please sign out and sign in again before deleting your account."
            } else {
                deleteErrorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Apple Deletion Confirmation Sheet

private struct AppleDeletionSheet: View {

    let onAuthorization: (ASAuthorization) -> Void

    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.myColors.myBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "person.crop.circle.badge.minus")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.myColors.myRed.opacity(0.7))

                VStack(spacing: 8) {
                    Text("Confirm Deletion")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.myColors.myAccent)

                    Text("Re-authenticate with Apple to permanently delete your account.")
                        .font(.body)
                        .foregroundStyle(Color.myColors.mySecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = authService.prepareAppleSignIn()
                } onCompletion: { result in
                    if case .success(let authorization) = result {
                        onAuthorization(authorization)
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)

                Button("Cancel") { dismiss() }
                    .font(.body)
                    .foregroundStyle(Color.myColors.mySecondary)

                Spacer()
            }
        }
    }
}

#Preview {
    NavigationStack { ProfileView() }
}
