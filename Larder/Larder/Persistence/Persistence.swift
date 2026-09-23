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
    ]

    /// Creates the app's model container. CloudKit is explicitly off for now;
    /// switching `cloudKitDatabase` to `.private("iCloud.<bundle id>")` (plus
    /// the iCloud entitlement) is all the model layer needs for private sync.
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
