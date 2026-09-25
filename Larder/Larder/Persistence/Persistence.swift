import Foundation
import SwiftData

enum Persistence {
    static let models: [any PersistentModel.Type] = [
        Product.self,
        ProductAlias.self,
        StorageLocation.self,
        InventoryItem.self,
        PurchaseEvent.self,
        UsageEvent.self,
        Receipt.self,
        ShoppingListItem.self,
        SavedRecipe.self,
        SyncRecordState.self,
    ]

    /// Creates the app's model container. SwiftData's own CloudKit mirroring
    /// stays off: it can't share with another iCloud account, so household
    /// sharing runs through `HomeSync` (CKSyncEngine) instead.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(
            "Larder",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
