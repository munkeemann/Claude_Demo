import SwiftData
import SwiftUI

@main
@MainActor
struct LarderApp: App {
    private let container: ModelContainer
    @State private var environment = AppEnvironment.live()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.applyAppearance()
        do {
            container = try Persistence.makeContainer()
        } catch {
            fatalError("Could not open the Larder database: \(error)")
        }
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
