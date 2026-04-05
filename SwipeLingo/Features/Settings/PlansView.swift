import SwiftUI

// MARK: - PlansView
// Plan comparison and selection screen.
// DEBUG: plan switching without payment — replace with StoreKit when billing is integrated.

struct PlansView: View {

    @AppStorage("userPlan") private var userPlan: AccessTier = .free
    @Environment(\.dismiss) private var dismiss

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

                    Button("Restore Purchases") { }
                        .font(.footnote)
                        .foregroundStyle(Color.myColors.myBlue)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                    }
                }
            }
        }
    }

    // MARK: - Plan Card

    private func planCard(_ plan: AccessTier) -> some View {
        let isSelected = userPlan == plan
        return Button { userPlan = plan } label: {
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
