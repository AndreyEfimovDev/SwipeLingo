import SwiftUI
import SwiftData

// MARK: - ExampleEditorSheet
//
// Шит управления пользовательскими примерами карточки — открывается с оборота карточки в TinderCards.
// Показывает только примеры, добавленные пользователем (userSampleEN/userSampleItem).
// Примеры из Firestore (sampleEN/sampleItem) не редактируются здесь — они управляются через Admin.
// Работает с локальными копиями массивов — изменения применяются только по нажатию Save.

struct ExampleEditorSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    let card: Card

    @State private var samplesEN:   [String]
    @State private var samplesItem: [String]

    init(card: Card) {
        self.card    = card
        _samplesEN   = State(initialValue: card.userSampleEN)
        _samplesItem = State(initialValue: card.userSampleItem)
    }

    private var hasChanges: Bool {
        samplesEN != card.userSampleEN || samplesItem != card.userSampleItem
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if samplesEN.isEmpty {
                    emptyState
                } else {
                    exampleList
                }
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Examples")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.myColors.myRed)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(hasChanges ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.4))
                        .disabled(!hasChanges)
                }
            }
        }
    }

    // MARK: List

    private var exampleList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(samplesEN.indices, id: \.self) { i in
                    exampleRow(at: i)
                    if i < samplesEN.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(16)
        }
    }

    @ViewBuilder
    private func exampleRow(at index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Номер примера
            Text("\(index + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.myColors.mySecondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            // Текст
            VStack(alignment: .leading, spacing: 4) {
                Text(samplesEN[index])
                    .font(.body)
                    .foregroundStyle(Color.myColors.myAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if index < samplesItem.count, !samplesItem[index].isEmpty {
                    Text(samplesItem[index])
                        .font(.subheadline.italic())
                        .foregroundStyle(Color.myColors.mySecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Удалить
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    deleteExample(at: index)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.myColors.myRed.opacity(0.5))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: Empty state (все примеры удалены до сохранения)

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.minus")
                .font(.system(size: 40))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.3))
            Text("No user examples")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.mySecondary)
            Text("Add examples from the Dictionary view.")
                .font(.caption)
                .foregroundStyle(Color.myColors.mySecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func deleteExample(at index: Int) {
        samplesEN.remove(at: index)
        if index < samplesItem.count {
            samplesItem.remove(at: index)
        }
    }

    private func save() {
        card.userSampleEN   = samplesEN
        card.userSampleItem = samplesItem
        context.saveWithErrorHandling()
        dismiss()
    }
}
