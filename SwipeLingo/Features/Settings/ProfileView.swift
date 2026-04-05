import SwiftUI
import SwiftData

// MARK: - ProfileView
// User profile screen: English level and subscription plan.
// DEBUG: plan switching without payment — replace with StoreKit when billing is integrated.

struct ProfileView: View {

    @AppStorage("userPlan") private var userPlan: AccessTier = .free
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                planSection
                levelSection
            }
            .padding(.vertical, 16)
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if profiles.isEmpty { context.insert(UserProfile()) }
        }
    }

    // MARK: - Plan

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PLAN")
                .font(.caption)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                ForEach(Array(AccessTier.allCases.enumerated()), id: \.offset) { index, tier in
                    if index > 0 { Divider().padding(.leading, 16) }
                    Button { userPlan = tier } label: {
                        HStack(spacing: 10) {
                            AccessTierBadge(tier: tier)
                            Text(tier.displayName)
                                .foregroundStyle(Color.myColors.myAccent)
                            Spacer()
                            if userPlan == tier {
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

            Text("DEBUG: tap to switch plan without payment")
                .font(.caption2)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.35))
                .padding(.horizontal, 32)
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
                        profile?.cefrLevel = level
                    } label: {
                        HStack(spacing: 10) {
                            Text(level.displayCode)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(level.color)
                                .frame(width: 36, alignment: .leading)
                            Text(level.displayName)
                                .foregroundStyle(Color.myColors.myAccent)
                            Spacer()
                            if profile?.cefrLevel == level {
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
}

#Preview {
    NavigationStack { ProfileView() }
}
