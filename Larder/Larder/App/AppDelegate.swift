import CloudKit
import InventoryCore
import SwiftData
import UIKit
import UserNotifications

/// The app's one model container, shared by the SwiftUI scene and by
/// notification actions that run before (or without) any UI.
@MainActor
enum AppContainer {
    static let shared: ModelContainer = {
        do {
            return try Persistence.makeContainer()
        } catch {
            fatalError("Could not open the Larder database: \(error)")
        }
    }()
}

/// Which tab is showing, so a notification tap can switch to Soon.
@Observable
@MainActor
final class AppRouter {
    static let shared = AppRouter()
    var selectedTab: RootView.Tab = .inventory
}

/// Handles notification taps and actions. iOS delivers these to a delegate
/// that has to be in place before launch finishes, which is why this lives
/// in an app delegate rather than a view.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationScheduler.registerCategories()
        return true
    }

    /// Routes invitation links (CloudKit shares) to `SceneDelegate`.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    /// Show reminders even while Larder is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case NotificationScheduler.tossedAction:
            let ids = (userInfo[NotificationScheduler.itemIDsKey] as? [String] ?? []).compactMap(UUID.init(uuidString:))
            await Reminders.markTossed(ids, container: AppContainer.shared)
        case UNNotificationDefaultActionIdentifier:
            if userInfo[NotificationScheduler.tabKey] as? String == "soon" {
                AppRouter.shared.selectedTab = .soon
            }
        default:
            break
        }
    }
}

/// Receives household invitations: tapping a Larder share link opens the
/// app here, whether it was running or not.
@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            HomeSync.shared.receive(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        HomeSync.shared.receive(cloudKitShareMetadata)
    }
}
