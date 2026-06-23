import SwiftUI

// MARK: - PaymentFormView
//
// Directs the user to the SwipeLingo website to complete payment.
// In-app payment is intentionally not implemented — all billing is handled
// on the website to comply with App Store Reader App guidelines.

struct PaymentFormView: View {

    let plan:         AccessTier
    let billingCycle: BillingCycle
    let onSuccess:    () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var subscribeURL: URL {
        Constants.subscribeURL(plan: plan.rawValue, cycle: billingCycle.rawValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Plan summary
                    planSummaryCard

                    // Explanation
                    VStack(spacing: 12) {
                        Image(systemName: "safari")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.myColors.myBlue)

                        Text("Subscribe on our website")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.myColors.myAccent)

                        Text("Payment is processed securely on the SwipeLingo website. You can pay by card (Russian or international) or via СБП.")
                            .font(.subheadline)
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 8)

                    // CTA button
                    Button {
                        openURL(subscribeURL)
                    } label: {
                        HStack(spacing: 8) {
                            Text("Go to Website")
                                .font(.body.weight(.semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.myColors.myBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    // After payment note
                    VStack(spacing: 6) {
                        Label("After payment, your plan updates automatically within a few minutes.", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Subscribe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Plan Summary

    private var planSummaryCard: some View {
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
            Text(String(format: "$%.2f", plan.price(for: billingCycle)))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.myColors.myAccent)
        }
        .padding(16)
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
    }
}
