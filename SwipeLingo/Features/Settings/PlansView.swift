import SwiftUI

// MARK: - PlansView
// Plan comparison and selection screen.
// DEBUG: plan switching without payment — replace with StoreKit when billing is integrated.

struct PlansView: View {

    @AppStorage("userPlan") private var userPlan: AccessTier = .free
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self)  private var authService
    @Environment(UserService.self)  private var userService

    @State private var selectedPlan: AccessTier = .free
    @State private var isSaving = false
    @State private var showAuth = false
    @State private var showTrialUsedAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Unlock your full potential")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                    ForEach(AccessTier.allCases, id: \.self) { plan in
                        planCard(plan)
                    }

                    Text("DEBUG: tap a plan to switch without payment")
                        .font(.caption2)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.35))
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.body)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Group {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color.myColors.myBlue)
                        } else {
                            let isCancellation = selectedPlan == .free && userPlan != .free
                            Button(isCancellation ? "Cancel Plan" : "Save") {
                                Task { await save() }
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(selectedPlan == userPlan
                                ? Color.myColors.myAccent.opacity(0.3)
                                : isCancellation ? Color.myColors.myRed : Color.myColors.myBlue)
                            .disabled(selectedPlan == userPlan)
                        }
                    }
                }
            }
            .onAppear { selectedPlan = userPlan }
            .alert("Trial Already Used", isPresented: $showTrialUsedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You've already used your free trial. To continue, choose a paid plan.")
            }
            .sheet(isPresented: $showAuth) {
                AuthView(isDismissible: true)
                    .environment(authService)
                    .onChange(of: authService.isAnonymous) { _, isAnon in
                        if !isAnon { showAuth = false }
                    }
            }
        }
    }

    private func save() async {
        // Trial requires a real account — prompt anonymous users to sign in first
        if selectedPlan != .free && userPlan == .free && authService.isAnonymous {
            showAuth = true
            return
        }
        isSaving = true
        defer { isSaving = false }
        if let uid = authService.currentUser?.uid {
            let success = await userService.updateSubscription(plan: selectedPlan, for: uid)
            if !success {
                showTrialUsedAlert = true
                return
            }
        } else {
            userPlan = selectedPlan
        }
        dismiss()
    }

    // MARK: - Plan Card

    private func planCard(_ plan: AccessTier) -> some View {
        let isSelected = selectedPlan == plan
        return Button { selectedPlan = plan } label: {
            VStack(alignment: .leading, spacing: 12) {

                // Header row
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(plan.displayName)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.myColors.myAccent)
                            AccessTierBadge(tier: plan)
                        }
                        Text(plan.priceLabel)
                            .font(.subheadline)
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                        if plan != .free && userPlan == .free {
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

                // Features list
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
}

#Preview {
    PlansView()
}
