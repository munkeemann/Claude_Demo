import Foundation
import InventoryCore
import SwiftData

/// A recipe the user favorited or cooked. The recipe itself is stored as
/// JSON so its shape can evolve without schema migrations.
@Model
final class SavedRecipe {
    /// Same as the `Recipe.id` it stores.
    var id: UUID = UUID()
    var title: String = ""
    var payload: Data = Data()
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var lastCookedAt: Date?
    var timesCooked: Int = 0

    init(recipe: Recipe, now: Date = Date()) {
        self.id = recipe.id
        self.title = recipe.title
        self.payload = (try? JSONEncoder().encode(recipe.withoutInventoryReferences)) ?? Data()
        self.createdAt = now
    }

    var recipe: Recipe? {
        try? JSONDecoder().decode(Recipe.self, from: payload)
    }
}
