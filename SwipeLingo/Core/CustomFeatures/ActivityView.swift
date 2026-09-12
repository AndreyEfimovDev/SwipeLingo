import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {

    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    let onComplete: (ActivityResult) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            let result = ActivityResult(
                activityType: activityType,
                completed: completed,
                returnedItems: returnedItems,
                error: error
            )
            onComplete(result)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ActivityResult {
    let activityType: UIActivity.ActivityType?
    let completed: Bool
    let returnedItems: [Any]?
    let error: Error?

    var activityName: String {
        activityType?.rawValue ?? "Unknown"
    }
}
