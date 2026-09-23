import Foundation
import InventoryCore
import SwiftData

extension InventoryStore {
    /// The in-stock ingredients offered to Claude, soonest-expiring first.
    func recipeRequest(filters: RecipeFilters) throws -> RecipeRequest {
        let today = now()
        let items = try context.fetch(FetchDescriptor<InventoryItem>())
            .filter { $0.status.isActive && ($0.product?.isIngredient ?? false) }
            .map { item -> RecipeCandidate in
                var amount = item.quantityLabel
                if item.unit.isDiscrete, let size = item.product?.packageSizeText {
                    amount += " × \(size)"
                }
                return (
                    itemID: item.id,
                    name: item.displayName,
                    brand: item.product?.brand,
                    category: item.product?.category ?? .other,
                    amount: amount,
                    daysUntilExpiry: item.expiryDate.map { ExpiryStatus(expiry: $0, now: today).daysRemaining }
                )
            }
        return RecipeRequest.build(items: items, filters: filters)
    }

    func item(id: UUID) throws -> InventoryItem? {
        var descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate<InventoryItem> { item in item.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func savedRecipe(id: UUID) throws -> SavedRecipe? {
        var descriptor = FetchDescriptor<SavedRecipe>(predicate: #Predicate<SavedRecipe> { saved in saved.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Finds or creates the saved copy of a recipe.
    private func upsertSavedRecipe(_ recipe: Recipe) throws -> SavedRecipe {
        if let existing = try savedRecipe(id: recipe.id) { return existing }
        let saved = SavedRecipe(recipe: recipe, now: now())
        context.insert(saved)
        return saved
    }

    func setFavorite(_ recipe: Recipe, _ isFavorite: Bool) throws {
        let saved = try upsertSavedRecipe(recipe)
        saved.isFavorite = isFavorite
        // Keep cooked history, but drop never-cooked recipes that are unfavorited.
        if !isFavorite && saved.timesCooked == 0 {
            context.delete(saved)
        }
        try context.save()
    }

    func isFavorite(_ recipe: Recipe) throws -> Bool {
        try savedRecipe(id: recipe.id)?.isFavorite ?? false
    }

    /// Adds each missing ingredient to the shopping list, noting the recipe.
    /// Returns how many entries were added or already present.
    @discardableResult
    func addMissingIngredients(of recipe: EvaluatedRecipe) throws -> Int {
        var count = 0
        for ingredient in recipe.missing {
            let product = try product(named: ingredient.ingredient.name, brand: nil)
            let entry = try addToShoppingList(
                name: ingredient.ingredient.name.capitalized,
                reason: .recipe,
                product: product,
                note: recipe.recipe.title
            )
            if entry != nil { count += 1 }
        }
        return count
    }

    /// Logs a "used some" event for every ingredient used, then records the
    /// recipe as cooked.
    func markCooked(_ recipe: Recipe, uses: [(item: InventoryItem, amount: Double)]) throws {
        for use in uses where use.amount > 0 && use.item.status.isActive {
            try apply(.usedSome(use.amount), to: use.item)
        }
        let saved = try upsertSavedRecipe(recipe)
        saved.timesCooked += 1
        saved.lastCookedAt = now()
        try context.save()
    }
}
