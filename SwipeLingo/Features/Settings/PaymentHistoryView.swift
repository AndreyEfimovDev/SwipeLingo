import SwiftUI

// MARK: - PaymentHistoryView
// Shows payment history loaded from Firestore: users/{uid}/paymentHistory

struct PaymentHistoryView: View {

    let uid: String

    @Environment(UserService.self) private var userService

    @State private var payments:   [PaymentRecord] = []
    @State private var isLoading   = true

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if payments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.3))
                    Text("No payments yet")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.mySecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(payments.enumerated()), id: \.element.id) { index, payment in
                            if index > 0 { Divider().padding(.leading, 16) }
                            paymentRow(payment)
                        }
                    }
                    .background(Color.myColors.myBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .myShadow()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .navigationTitle("Payment History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            payments  = await userService.loadPaymentHistory(for: uid)
            isLoading = false
        }
    }

    private func paymentRow(_ payment: PaymentRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    let tier = AccessTier(rawValue: payment.plan) ?? .free
                    AccessTierBadge(tier: tier)
                    Text(tier.displayName)
                        .font(.body)
                        .foregroundStyle(Color.myColors.myAccent)
                    let cycle = BillingCycle(rawValue: payment.billingCycle) ?? .none
                    if cycle != .none {
                        Text("· \(cycle.displayName)")
                            .font(.subheadline)
                            .foregroundStyle(Color.myColors.mySecondary)
                    }
                }
                Text(dateFormatter.string(from: payment.date))
                    .font(.caption)
                    .foregroundStyle(Color.myColors.mySecondary)
                if let last4 = payment.last4, !last4.isEmpty {
                    Text("•••• \(last4)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.myColors.mySecondary.opacity(0.7))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "$%.2f", payment.amount))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent)
                Text(payment.currency)
                    .font(.caption2)
                    .foregroundStyle(Color.myColors.mySecondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
    }
}
