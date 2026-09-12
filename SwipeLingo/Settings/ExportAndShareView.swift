import SwiftUI
import SwiftData

struct ExportAndShareView: View {

    @Environment(\.modelContext) private var modelContext

    @State private var isExporting    = false
    @State private var shareURL: URL? = nil
    @State private var showShareSheet = false

    private let service = ExportService()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                exportCard
            }
            .padding(.vertical, 16)
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .navigationTitle("Export / Share")
        .navigationBarTitleDisplayMode(.inline)
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
                Text("Exports cards from Inbox and My Sets — including translations, examples, and SRS study progress — to a JSON file. Share via AirDrop, Mail, or save to Files.")
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
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    private func prepareExport() {
        isExporting = true
        let ctx = modelContext
        Task.detached {
            let result = await ExportService().exportAll(from: ctx)
            await MainActor.run {
                isExporting = false
                switch result {
                case .success(let url):
                    shareURL = url
                    showShareSheet = true
                case .failure(let error):
                    log("Export error: \(error)", level: .error)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { ExportAndShareView() }
}
