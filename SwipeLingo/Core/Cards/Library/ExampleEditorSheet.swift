import SwiftUI
import SwiftData

// MARK: - ExampleEditorSheet
//
// Шит управления примерами карточки — открывается долгим нажатием на пример на обороте карточки в TinderCards.
// Показывает все примеры карточки. У пользовательской карточки удаляются любые, у облачной — только
// добавленные со словаря (см. ExampleEditorViewModel). Изменения применяются только по нажатию Save.

struct ExampleEditorSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    private let card: Card

    @State private var vm: ExampleEditorViewModel

    /// - Parameters:
    ///   - card: карточка, примеры которой редактируются.
    ///   - isUserCard: карточка из пользовательского сета (`CardSet.isUserCreated`).
    init(card: Card, isUserCard: Bool) {
        self.card = card
        _vm = State(initialValue: ExampleEditorViewModel(card: card, isUserCard: isUserCard))
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if vm.rows.isEmpty {
                    emptyState
                } else {
                    exampleList
                }
            }
            .background(Color.myColors.mySheetBackground.ignoresSafeArea())
            .sheetNavigationBar("Examples")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    NavBarButtonForSheet(title: "Cancel", color: Color.myColors.myRed) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    NavBarButtonForSheet(
                        title: "Save",
                        color: vm.hasChanges ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.8)
                    ) { save() }
                        .disabled(!vm.hasChanges)
                }
            }
        }
    }

    // MARK: List

    private var exampleList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                let rows = vm.rows
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                        exampleRow(row, number: position + 1)
                        if position < rows.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color.myColors.mySheetBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .myShadow()

                if vm.hasLockedRows {
                    Text("SwipeLingo examples can't be removed")
                        .font(.caption)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                        .padding(.horizontal, 16)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func exampleRow(_ row: ExampleEditorViewModel.Row, number: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Номер примера
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            // Текст
            VStack(alignment: .leading, spacing: 4) {
                Text(row.en)
                    .font(.body)
                    .foregroundStyle(Color.myColors.myAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let translation = row.translation {
                    Text(translation)
                        .font(.subheadline.italic())
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Удалить — только у удаляемых примеров
            if row.isRemovable {
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        vm.delete(row)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.myColors.myRed.opacity(0.5))
                }
                .buttonStyle(.borderless)
            }
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
            Text("No examples")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            Text("Add examples from the Dictionary view.")
                .font(.caption)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func save() {
        vm.apply(to: card)
        context.saveWithErrorHandling()
        dismiss()
    }
}
