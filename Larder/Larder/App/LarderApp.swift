import SwiftData
import SwiftUI

@main
@MainActor
struct LarderApp: App {
    private let container: ModelContainer
    @State private var environment = AppEnvironment.live()

    init() {
        do {
            container = try Persistence.makeContainer()
        } catch {
            fatalError("Could not open the Larder database: \(error)")
        }
        do {
            try InventoryStore(context: container.mainContext).seedLocationsIfNeeded()
        } catch {
            assertionFailure("Seeding locations failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
        .modelContainer(container)
    }
}
