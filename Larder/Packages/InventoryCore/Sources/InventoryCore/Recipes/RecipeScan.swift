import Foundation

/// Photos of a recipe someone cooked (a cookbook page, a recipe card, a
/// screenshot), with the inventory its ingredients came from.
public struct RecipeScanInput: Sendable, Equatable {
    public var images: [Data]
    public var items: [RecipeInventoryItem]

    public init(images: [Data], items: [RecipeInventoryItem]) {
        self.images = images.filter { !$0.isEmpty }
        self.items = items
    }
}

public enum RecipeScanPrompt {
    public static let system = """
    You read recipes from photos (cookbook pages, recipe cards, handwritten notes, screenshots) for a \
    home inventory app. Someone cooked this recipe, and the app will subtract its ingredients from \
    their inventory. You also get that inventory, each item with a short id like "i3".

    Rules:
    - Transcribe the recipe: title, servings, every ingredient with its amount as written ("2 cups", \
    "1 lb", "3 cloves"), and the steps in order. If the photos span several pages, combine them.
    - For each ingredient the household has, set inventoryItemId to that item's id and have to true. \
    Match on what the food is, not the exact wording ("yellow onion" is "Onions"). Use each id only \
    for an item that truly matches; otherwise inventoryItemId is null and have is false.
    - Mark salt, pepper, oil, water and other basic staples with isStaple true.
    - summary: one sentence on what the dish is. mealType: your best guess. totalMinutes: as \
    written, or a reasonable estimate.
    - If there's no recipe in the photos, return a recipe titled "No recipe found" with no ingredients.
    """

    public static func userText(for input: RecipeScanInput) -> String {
        var sections: [String] = []
        if input.images.count > 1 {
            sections.append("These \(input.images.count) photos are pages of one recipe.")
        }
        if input.items.isEmpty {
            sections.append("The inventory is empty.")
        } else {
            let lines = input.items.map { item -> String in
                let brand = item.brand.map { " (\($0))" } ?? ""
                return "- \(item.promptID) | \(item.name)\(brand) | \(item.amount)"
            }
            sections.append("Inventory (id | item | amount):\n" + lines.joined(separator: "\n"))
        }
        sections.append("Read the recipe.")
        return sections.joined(separator: "\n\n")
    }

    public static var schema: JSONValue { RecipePrompt.recipeSchema }

    /// True when Claude found no recipe to read.
    public static func isEmpty(_ recipe: Recipe) -> Bool {
        recipe.ingredients.isEmpty
    }
}
