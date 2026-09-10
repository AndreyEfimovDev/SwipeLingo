import SwiftUI
import SwiftData

struct RestoreBackupView: View {

    @Environment(\.modelContext) private var modelContext

    @State private var isImporting        = false
    @State private var showDocumentPicker = false
    @State private var importResult: ExportService.ImportResult? = nil
    @State private var importError: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                restoreCard
            }
            .padding(.vertical, 16)
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .navigationTitle("Restore")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in
                handleDocumentPicked(url: url)
            } onCancel: {
                isImporting = false
            }
        }
    }

    private var restoreCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RESTORE")
                .font(.caption)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                Text("Restores Inbox and My Sets cards from a SwipeLingo backup file. Cards that already exist are not modified.")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.mySecondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider().padding(.leading, 16)

                Button {
                    importResult = nil
                    importError  = nil
                    isImporting  = true
                    showDocumentPicker = true
                } label: {
                    HStack {
                        Label("Choose Backup File", systemImage: "tray.and.arrow.down")
                            .labelStyle(.fixedIcon)
                        Spacer()
                        if isImporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        }
                    }
                    .font(.body)
                    .foregroundStyle(isImporting ? Color.myColors.mySecondary : Color.myColors.myBlue)
                    .frame(height: 52)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isImporting)

                if let result = importResult {
                    Divider().padding(.leading, 16)
                    resultRow(result)
                }

                if let error = importError {
                    Divider().padding(.leading, 16)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.myColors.myRed)
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

    private func resultRow(_ result: ExportService.ImportResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.myColors.myGreen)
            if result.newCards == 0 && result.newSets == 0 {
                Text("Everything is already up to date")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.mySecondary)
            } else {
                Text("Added \(result.newCards) card(s) in \(result.newSets) set(s)")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.mySecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func handleDocumentPicked(url: URL) {
        let ctx = modelContext
        Task.detached {
            let r = await ExportService().importBackup(from: url, into: ctx)
            await MainActor.run {
                isImporting  = false
                importResult = r
            }
        }
    }
}

#Preview {
    NavigationStack { RestoreBackupView() }
}
