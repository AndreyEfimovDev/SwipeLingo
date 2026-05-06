import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - ProfileView
// User profile: name, auth state, subscription plan, English level.

struct ProfileView: View {

    @AppStorage("userPlan") private var userPlan: AccessTier = .free
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var authService

    @State private var showAuth    = false
    @State private var showPlans   = false
    @State private var didCopyUID  = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                nameSection
                accountSection
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
        .onDisappear {
            context.saveWithErrorHandling()
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

                    TextField("Anonymous", text: Binding(
                        get: { profile?.name ?? "" },
                        set: { profile?.name = $0 }
                    ))
                    .font(.body)
                    .foregroundStyle(Color.myColors.myAccent)
                    .submitLabel(.done)
                    .onSubmit { context.saveWithErrorHandling() }
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
                        Spacer()
                    }
                    .frame(height: 52)
                    .padding(.horizontal, 16)

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
                }
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Plan

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PLAN")
                .font(.caption)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    AccessTierBadge(tier: userPlan)
                    Text(userPlan.displayName)
                        .font(.body)
                        .foregroundStyle(Color.myColors.myAccent)
                    Spacer()
                }
                .frame(height: 52)
                .padding(.horizontal, 16)

                Divider().padding(.leading, 16)

                Button { showPlans = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: userPlan == .free ? "star.circle" : "gearshape.circle")
                            .font(.title2)
                            .foregroundStyle(Color.myColors.myBlue)
                        Text(userPlan == .free ? "Subscribe to Go or Pro" : "Manage Subscription")
                            .font(.body)
                            .foregroundStyle(userPlan == .free ? Color.myColors.myBlue : Color.myColors.myAccent)
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
