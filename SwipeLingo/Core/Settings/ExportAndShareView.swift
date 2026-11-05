import SwiftUI
import SwiftData
import FirebaseAuth

struct ExportAndShareView: View {

    /// Нужен только для `firebaseUID` — экспортировать сеты СВОЕГО аккаунта (см.
    /// `Collection.isMine(firebaseUID:)`), не другого, оставшегося локально на том же iCloud.
    let authService: AuthFBService

    @Environment(\.modelContext) private var modelContext

    @State private var isExporting    = false
    @State private var shareURL: URL? = nil
    @State private var showShareSheet = false
    @State private var exportError: String? = nil
    @State private var exportTask: Task<Void, Never>?

    private let service = ExportService()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                exportCard
            }
            .padding(.vertical, 16)
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .customBackButton("")
        .navigationTitle("Export / Share")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { exportTask?.cancel() }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ActivityView(activityItems: [url], applicationActivities: nil) { result in
                    if result.completed {
                        log("Shared via: \(result.activityName)", level: .info)
                    }
                    service.cleanupTempFile(url)
                    shareURL = nil
                    showShareSheet = false
                }
            }
        }
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXPORT")
                .font(.caption)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                Text("Exports cards from Inbox and your collections — including translations, examples, and SRS study progress — to a JSON file. Share via AirDrop, Mail, or save to Files.")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.mySecondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider().padding(.leading, 16)

                Button { prepareExport() } label: {
                    HStack {
                        Label("Export & Share", systemImage: "square.and.arrow.up")
                            .labelStyle(.fixedIcon)
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        }
                    }
                    .font(.body)
                    .foregroundStyle(isExporting ? Color.myColors.mySecondary : Color.myColors.myBlue)
                    .frame(height: 52)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isExporting)

                if let error = exportError {
                    Divider().padding(.leading, 16)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.myColors.myRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    private func prepareExport() {
        isExporting = true
        exportError = nil
        let ctx = modelContext
        let firebaseUID = authService.currentUser?.uid ?? ""
        // ExportService работает на MainActor (изоляция по умолчанию), так что Task.detached ничего не давал.
        // yield — чтобы спиннер успел появиться до синхронного экспорта.
        exportTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            let result = service.exportAll(from: ctx, firebaseUID: firebaseUID)
            isExporting = false
            switch result {
            case .success(let url):
                shareURL = url
                showShareSheet = true
            case .failure(let error):
                // Показываем на самом экране: общий алерт ErrorManager висит на AppView и поверх
                // полноэкранных Settings не виден.
                log("Export error: \(error)", level: .error)
                exportError = "Couldn't create the backup file. Please try again."
            }
        }
    }
}

#Preview {
    NavigationStack { ExportAndShareView(authService: AuthFBService()) }
}
