import SwiftUI
import FirebaseAuth

// MARK: - PaymentFormView
// Simulated payment form. Always succeeds — replace with real payment SDK later.

struct PaymentFormView: View {

    let plan:         AccessTier
    let billingCycle: BillingCycle
    let onSuccess:    () -> Void

    @Environment(\.dismiss)         private var dismiss
    @Environment(AuthService.self)  private var authService
    @Environment(UserService.self)  private var userService

    @AppStorage(Constants.StorageKey.userPlan)           private var currentPlanRaw:  String = AccessTier.free.rawValue
    @AppStorage(Constants.StorageKey.cachedBillingCycle) private var currentCycleRaw: String = BillingCycle.none.rawValue

    @State private var rawCardNumber = ""
    @State private var expiry        = ""
    @State private var cvv           = ""
    @State private var isPaying      = false
    @State private var showError     = false

    private var currentPlan:  AccessTier   { AccessTier(rawValue: currentPlanRaw)     ?? .free }
    private var currentCycle: BillingCycle { BillingCycle(rawValue: currentCycleRaw)  ?? .none }

    private var cachedExpiry: Date? {
        let ts = UserDefaults.standard.double(forKey: Constants.StorageKey.cachedPlanExpiry)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    private var chargeAmount: Double {
        AccessTier.chargeAmount(
            from: currentPlan, currentCycle: currentCycle, expiry: cachedExpiry,
            to: plan, targetCycle: billingCycle
        )
    }

    private var isProrated: Bool {
        chargeAmount < plan.price(for: billingCycle) && currentPlan != .free
    }

    private var displayCardNumber: String {
        let digits = String(rawCardNumber.prefix(16))
        return stride(from: 0, to: digits.count, by: 4).map {
            let start = digits.index(digits.startIndex, offsetBy: $0)
            let end   = digits.index(start, offsetBy: min(4, digits.count - $0))
            return String(digits[start..<end])
        }.joined(separator: " ")
    }

    private var cardLast4: String {
        String(rawCardNumber.suffix(4))
    }

    private var isFormValid: Bool {
        rawCardNumber.count == 16 && expiry.count == 5 && cvv.count >= 3
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    planSummaryCard
                    cardFieldsCard
                    payButton
                    disclaimer
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                        .disabled(isPaying)
                }
            }
            .alert("Payment Failed", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Something went wrong. Please try again.")
            }
        }
    }

    // MARK: - Plan Summary

    private var planSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AccessTierBadge(tier: plan)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(plan.displayName)
                            .font(.headline)
                            .foregroundStyle(Color.myColors.myAccent)
                        Text("·")
                            .foregroundStyle(Color.myColors.mySecondary)
                        Text(billingCycle.displayName)
                            .font(.subheadline)
                            .foregroundStyle(Color.myColors.mySecondary)
                    }
                    Text(plan.priceString(for: billingCycle))
                        .font(.caption)
                        .foregroundStyle(Color.myColors.mySecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if isProrated {
                        Text(String(format: "$%.2f", plan.price(for: billingCycle)))
                            .font(.caption)
                            .strikethrough()
                            .foregroundStyle(Color.myColors.mySecondary)
                    }
                    Text(String(format: "$%.2f", chargeAmount))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.myColors.myAccent)
                }
            }
            if isProrated, let expiry = cachedExpiry {
                let credit = plan.price(for: billingCycle) - chargeAmount
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Full price")
                            .font(.caption)
                            .foregroundStyle(Color.myColors.mySecondary)
                        Spacer()
                        Text(String(format: "$%.2f", plan.price(for: billingCycle)))
                            .font(.caption)
                            .foregroundStyle(Color.myColors.mySecondary)
                    }
                    HStack {
                        Text("Credit for unused \(currentPlan.displayName) time")
                            .font(.caption)
                            .foregroundStyle(Color.myColors.myGreen)
                        Spacer()
                        Text(String(format: "−$%.2f", credit))
                            .font(.caption)
                            .foregroundStyle(Color.myColors.myGreen)
                    }
                    HStack {
                        Text("Valid until")
                            .font(.caption)
                            .foregroundStyle(Color.myColors.mySecondary)
                        Spacer()
                        Text(expiry, style: .date)
                            .font(.caption)
                            .foregroundStyle(Color.myColors.mySecondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
    }

    // MARK: - Card Fields

    private var cardFieldsCard: some View {
        VStack(spacing: 0) {
            // Card number
            HStack(spacing: 12) {
                Image(systemName: "creditcard")
                    .font(.title3)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                    .frame(width: 28)
                TextField("Card number", text: Binding(
                    get: { displayCardNumber },
                    set: { newVal in
                        let digits = newVal.filter(\.isNumber)
                        rawCardNumber = String(digits.prefix(16))
                    }
                ))
                .keyboardType(.numberPad)
                .font(.body.monospacedDigit())
                .foregroundStyle(Color.myColors.myAccent)
            }
            .frame(height: 52)
            .padding(.horizontal, 16)

            Divider().padding(.leading, 56)

            // Expiry + CVV
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                        .frame(width: 28)
                    TextField("MM/YY", text: $expiry)
                        .keyboardType(.numberPad)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(Color.myColors.myAccent)
                        .onChange(of: expiry) { _, new in
                            let digits = new.filter(\.isNumber)
                            let capped = String(digits.prefix(4))
                            if capped.count >= 3 {
                                expiry = String(capped.prefix(2)) + "/" + String(capped.dropFirst(2))
                            } else {
                                expiry = capped
                            }
                        }
                }
                .frame(height: 52)
                .padding(.horizontal, 16)

                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "lock")
                        .font(.title3)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                        .frame(width: 28)
                    SecureField("CVV", text: $cvv)
                        .keyboardType(.numberPad)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(Color.myColors.myAccent)
                        .onChange(of: cvv) { _, new in
                            let digits = new.filter(\.isNumber)
                            cvv = String(digits.prefix(4))
                        }
                }
                .frame(height: 52)
                .padding(.horizontal, 16)
            }
        }
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
    }

    // MARK: - Pay Button

    private var payButton: some View {
        Button {
            Task { await pay() }
        } label: {
            Group {
                if isPaying {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(String(format: "Pay $%.2f", chargeAmount))
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isFormValid ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.2))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!isFormValid || isPaying)
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        Text("This is a simulated payment. No real charge will occur.")
            .font(.caption2)
            .foregroundStyle(Color.myColors.mySecondary.opacity(0.6))
            .multilineTextAlignment(.center)
            .padding(.bottom, 8)
    }

    // MARK: - Action

    private func pay() async {
        isPaying = true
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 800_000_000)

        guard let uid = authService.currentUser?.uid else {
            isPaying = false
            showError = true
            return
        }

        let success = await userService.purchaseSubscription(
            plan: plan,
            billingCycle: billingCycle,
            amount: chargeAmount,
            cardLast4: cardLast4,
            for: uid
        )

        isPaying = false
        if success {
            onSuccess()
            dismiss()
        } else {
            showError = true
        }
    }
}
