import SwiftUI

// MARK: - ShareExtensionView
// Bottom-sheet style UI shown inside the Share Extension.
// Displays the selected word and offers "Add to Inbox" / Cancel actions.
//
// Length validation via CardLengthValidator (shared file, both targets):
//   ≤ 50 chars  — OK, no hint
//   51–150 chars — warning, Add still allowed
//   > 150 chars  — blocked, Add disabled

struct ShareExtensionView: View {

    let word: String
    let onAdd:    () -> Void
    let onCancel: () -> Void

    private var wordCount: Int {
        word.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var lengthState: CardLengthState {
        CardLengthValidator.state(for: word)
    }

    var body: some View {
        VStack(spacing: 10) {

            // Handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.myColors.myAccent)
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            // Header
            Text("Add to SwipeLingo Inbox")
                .font(.headline)
                .foregroundStyle(Color.myColors.myAccent)
                .padding(.top, 16)

            // Word preview
            Text(word)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.myColors.myGreen)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, lengthState == .ok ? 28 : 8)

            // Length hint (only in warning / tooLong states)
            if lengthState != .ok {
                lengthHint
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }

            // Buttons
            VStack(spacing: 8) {
                Button {
                    onAdd()
                } label: {
                    Text("Add")
                        .font(.body.weight(.semibold))
                        .buttonRect(color: lengthState == .tooLong
                            ? Color.myColors.myAccent.opacity(0.3)
                            : Color.myColors.myBlue)
                }
                .disabled(lengthState == .tooLong)

                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.body)
                        .buttonRect(color: Color.myColors.myRed)
                }
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 24)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Length Hint

    @ViewBuilder
    private var lengthHint: some View {
        let max = CardLengthValidator.maxLength
        switch lengthState {
        case .ok:
            EmptyView()
        case .warning:
            Label(
                "Long phrase (\(wordCount) chars) — cards work best with short words. You can still add it.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(Color.myColors.myOrange)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        case .tooLong:
            Label(
                "Too long for a card (\(wordCount)/\(max) chars). Select a shorter word or phrase.",
                systemImage: "xmark.circle"
            )
            .font(.caption)
            .foregroundStyle(Color.myColors.myRed)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }
}
