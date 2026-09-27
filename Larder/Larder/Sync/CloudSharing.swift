import CloudKit
import UIKit

/// Presents Apple's sharing sheet (invite by Messages, Mail or link; manage
/// people; stop sharing) over whatever is on screen.
@MainActor
enum CloudSharing {
    /// Kept alive while the sheet is up; UIKit holds its delegate weakly.
    private static var activeDelegate: Delegate?

    static func present(share: CKShare, container: CKContainer, title: String, onChange: @escaping () -> Void) {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        let delegate = Delegate(title: title, onChange: onChange)
        controller.delegate = delegate
        activeDelegate = delegate
        topViewController()?.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private final class Delegate: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let onChange: () -> Void

        init(title: String, onChange: @escaping () -> Void) {
            self.title = title
            self.onChange = onChange
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onChange()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onChange()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onChange()
        }
    }
}
