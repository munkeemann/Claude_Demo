import SwiftData
import SwiftUI

@main
@MainActor
struct LarderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer
    @State private var environment = AppEnvironment.live()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.applyAppearance()
        container = AppContainer.shared
        do {
            let store = InventoryStore(context: container.mainContext)
            try store.seedLocationsIfNeeded()
            try store.refreshEstimatedExpiries()
        } catch {
            assertionFailure("Launch maintenance failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await Reminders.refresh(container: container) }
            case .background:
                BackgroundRefresh.schedule()
                Task { await Reminders.refresh(container: container) }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [container] in
            BackgroundRefresh.schedule()
            await Reminders.refresh(container: container)
        }
    }
}
