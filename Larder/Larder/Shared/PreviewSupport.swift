import SwiftData
import SwiftUI

/// In-memory container pre-filled with `SampleData`, for SwiftUI previews.
@MainActor
enum PreviewSupport {
    static let container: ModelContainer = {
        do {
            let container = try Persistence.makeContainer(inMemory: true)
            try InventoryStore(context: container.mainContext).loadSampleData()
            return container
        } catch {
            fatalError("Preview container failed: \(error)")
        }
    }()

    static func firstItem(named name: String) -> InventoryItem? {
        let items = (try? container.mainContext.fetch(FetchDescriptor<InventoryItem>())) ?? []
        return items.first { $0.product?.name == name } ?? items.first
    }
}
