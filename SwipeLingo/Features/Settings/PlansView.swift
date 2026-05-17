import SwiftUI
import FirebaseAuth

// MARK: - PlansView

struct PlansView: View {

    @AppStorage(Constants.StorageKey.userPlan)          private var userPlan:    AccessTier = .free
    @AppStorage(Constants.StorageKey.cachedPlanStatus)  private var planStatus:  String     = SubscriptionStatus.active.rawValue
    @AppStorage(Constants.StorageKey.cachedBillingCycle) private var planCycle:  String     = BillingCycle.none.rawValue

    @Environment(\.dismiss)        private var dismiss
    @Environment(AuthService.self)  private var authService
    @Environment(UserService.self)  private var userService

    @State private var selectedPlan:  AccessTier    = .free
    @State private var selectedCycle: BillingCycle  = .yearly
    @State private var showPaymentForm    = false
    @State private var showCancelConfirm  = false
    @State private var showTrialUsedAlert = false
    @State private var showAuthSheet      = false
    @State private var isSaving           = false

    private var currentStatus: SubscriptionStatus {
        SubscriptionStatus(rawValue: planStatus) ?? .active
    }
    private var currentCycle: BillingCycle {
        BillingCycle(rawValue: planCycle) ?? .none
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Unlock your full potential")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                        .padding(.top, 4)

                    billingCyclePicker

                    ForEach(AccessTier.allCases, id: \.self) { plan in
                        planCard(plan)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Plans")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                actionButton
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.myColors.myBackground)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                        .disabled(isSaving)
                }
            }
            .onAppear {
                selectedPlan  = userPlan
                selectedCycle = currentCycle == .none ? .yearly : currentCycle
            }
            .confirmationDialog(
                selectedPlan == .free ? "Cancel Subscription" : "Schedule Downgrade",
                isPresented: $showCancelConfirm,
                titleVisibility: .visible
            ) {
                Button(selectedPlan == .free ? "Cancel Subscription" : "Confirm Downgrade", role: .destructive) {
                    Task { await handleCancel() }
                }
                Button("Keep Current Plan", role: .cancel) { }
            } message: {
                Text("Your current plan stays active until the end of the billing period. After that it switches to the new plan.")
            }
            .alert("Trial Already Used", isPresented: $showTrialUsedAlert) {
                Button("Subscribe") { showPaymentForm = true }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You've already used your free trial. Subscribe to continue.")
            }
            .sheet(isPresented: $showPaymentForm) {
                PaymentFormView(
                    plan: selectedPlan,
                    billingCycle: selectedCycle,
                    onSuccess: { dismiss() }
                )
                .environment(authService)
                .environment(userService)
            }
            .sheet(isPresented: $showAuthSheet) {
                AuthView(isDismissible: true)
                    .environment(authService)
                    .onChange(of: authService.isAnonymous) { _, isAnon in
                        if !isAnon { showAuthSheet = false }
                    }
            }
        }
    }

    // MARK: - Billing Cycle Picker

    private var billingCyclePicker: some View {
        Picker("Billing", selection: $selectedCycle) {
            Text("Monthly").tag(BillingCycle.monthly)
            Text("Annual").tag(BillingCycle.yearly)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Plan Card

    private func planCard(_ plan: AccessTier) -> some View {
        let isSelected = selectedPlan == plan
        let isCurrent  = plan == userPlan && selectedCycle == currentCycle
            && currentStatus == .active

        return Button { selectedPlan = plan } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(plan.displayName)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.myColors.myAccent)
                            AccessTierBadge(tier: plan)
                            if isCurrent {
                                Text("current")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.myColors.myBlue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.myColors.myBlue.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(plan.priceString(for: selectedCycle))
                            .font(.subheadline)
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                        if plan != .free && selectedCycle == .yearly {
                            let monthly = plan.price(for: .monthly)
                            let annual  = plan.price(for: .yearly)
                            let saving  = Int((1 - annual / (monthly * 12)) * 100)
                            Text("Save \(saving)% vs monthly")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.myColors.myGreen)
                        }
                        if plan != .free && userPlan == .free && currentStatus != .trial {
                            Text("\(Constants.trialDurationDays)-day free trial")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.myColors.myGreen)
                        }
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.3))
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(plan.features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.myColors.myBlue)
                                .frame(width: 16)
                            Text(feature)
                                .font(.subheadline)
                                .foregroundStyle(Color.myColors.myAccent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.15),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .myShadow()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Group {
            if isSaving {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                let config = buttonConfig
                Button {
                    handleAction(config.action)
                } label: {
                    Text(config.label)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(config.isDestructive
                            ? Color.myColors.myRed.opacity(0.85)
                            : config.isDisabled
                                ? Color.myColors.myAccent.opacity(0.15)
                                : Color.myColors.myBlue)
                        .foregroundStyle(config.isDisabled ? Color.myColors.mySecondary : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(config.isDisabled)
            }
        }
    }

    // MARK: - Button config

    private struct ButtonConfig {
        var label:         String
        var action:        ActionKind
        var isDestructive: Bool = false
        var isDisabled:    Bool = false
    }

    private enum ActionKind {
        case startTrial, subscribe, change, scheduleDowngrade, cancel, none
    }

    private var isDowngrade: Bool {
        guard userPlan != .free else { return false }
        if selectedPlan.rank < userPlan.rank { return true }
        if selectedPlan == userPlan && currentCycle == .yearly && selectedCycle == .monthly { return true }
        return false
    }

    private var buttonConfig: ButtonConfig {
        // Cancel subscription
        if selectedPlan == .free && userPlan != .free {
            return ButtonConfig(label: "Cancel Subscription", action: .cancel, isDestructive: true)
        }
        // Nothing changed (active paid user, same plan+cycle)
        if selectedPlan == userPlan && selectedCycle == currentCycle && currentStatus == .active {
            return ButtonConfig(label: "Current Plan", action: .none, isDisabled: true)
        }
        // Free plan selected (already free)
        if selectedPlan == .free && userPlan == .free {
            return ButtonConfig(label: "Current Plan", action: .none, isDisabled: true)
        }
        // Free user → trial available
        if userPlan == .free && currentStatus != .trial && selectedPlan != .free {
            return ButtonConfig(label: "Start Free Trial", action: .startTrial)
        }
        // On trial → convert to paid
        if currentStatus == .trial && selectedPlan != .free {
            return ButtonConfig(label: "Subscribe Now", action: .subscribe)
        }
        // Downgrade (lower tier or Annual→Monthly) — scheduled, no payment
        if isDowngrade {
            return ButtonConfig(label: "Schedule Downgrade", action: .scheduleDowngrade)
        }
        // Upgrade (higher tier or Monthly→Annual) — requires payment
        return ButtonConfig(label: "Upgrade Plan", action: .change)
    }

    // MARK: - Actions

    private func handleAction(_ action: ActionKind) {
        switch action {
        case .startTrial:
            if authService.isAnonymous { showAuthSheet = true; return }
            Task { await handleStartTrial() }
        case .subscribe, .change:
            showPaymentForm = true
        case .scheduleDowngrade:
            showCancelConfirm = true
        case .cancel:
            showCancelConfirm = true
        case .none:
            break
        }
    }

    private func handleStartTrial() async {
        guard let uid = authService.currentUser?.uid else { return }
        isSaving = true
        defer { isSaving = false }
        let started = await userService.startTrial(pendingPlan: selectedPlan, for: uid)
        if started { dismiss() } else { showTrialUsedAlert = true }
    }

    private func handleCancel() async {
        guard let uid = authService.currentUser?.uid else { return }
        isSaving = true
        defer { isSaving = false }
        if selectedPlan == .free {
            await userService.cancelSubscription(for: uid)
        } else {
            await userService.scheduleDowngrade(plan: selectedPlan, billingCycle: selectedCycle, for: uid)
        }
        dismiss()
    }
}

#Preview {
    PlansView()
}
