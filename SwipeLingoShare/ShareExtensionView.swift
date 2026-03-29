import SwiftUI

// MARK: - ShareExtensionView
// Bottom-sheet style UI shown inside the Share Extension.
// Displays the selected word and offers "Add to Inbox" / Cancel actions.

struct ShareExtensionView: View {

    let word: String
    let onAdd:    () -> Void
    let onCancel: () -> Void

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
                .padding(.bottom, 28)

            // Buttons
            VStack(spacing: 8) {
                Button {
                    onAdd()
                } label: {
                    Text("Add")
                        .font(.body.weight(.semibold))
                        .buttonRect(color: Color.myColors.myBlue)
                }

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
}
