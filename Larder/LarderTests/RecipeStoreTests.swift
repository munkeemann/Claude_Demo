import Foundation
import InventoryCore
import SwiftData
import Testing
@testable import Larder

@MainActor
struct RecipeStoreTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    let container: ModelContainer
    let store: InventoryStore

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        store = InventoryStore(context: container.mainContext, now: { Self.now })
        try store.seedLocationsIfNeeded()
        try store.loadSampleData()
    }

    func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try container.mainContext.fetch(FetchDescriptor<T>())
    }

    func evaluated(_ recipe: Recipe, filters: RecipeFilters = RecipeFilters()) throws -> EvaluatedRecipe {
        let request = try store.recipeRequest(filters: filters)
        return IngredientMatcher.evaluate(recipe, items: request.items, assumeStaples: filters.assumeStaples)
    }

    @Test func requestIncludesOnlyInStockIngredientsSoonestFirst() throws {
        let request = try store.recipeRequest(filters: RecipeFilters())
        let names = request.items.map(\.name)
        #expect(names.contains("Baby Spinach"))
        #expect(!names.contains("Dish Soap"), "Household goods are not ingredients")
        #expect(!names.contains("Whole Bean Coffee"), "Beverages are not ingredients by default")
        let days = request.items.compactMap(\.daysUntilExpiry)
        #expect(days == days.sorted())
        #expect(request.items.first?.promptID == "i1")
    }

    @Test func usedUpItemsAreNotOffered() throws {
        let spinach = try #require(try fetchAll(InventoryItem.self).first { $0.displayName == "Baby Spinach" })
        try store.apply(.usedUp, to: spinach)
        let names = try store.recipeRequest(filters: RecipeFilters()).items.map(\.name)
        #expect(!names.contains("Baby Spinach"))
    }

    @Test func missingIngredientsGoToTheShoppingList() throws {
        let pasta = try evaluated(SampleRecipes.recipes[1])
        #expect(pasta.missingCount == 1)
        let added = try store.addMissingIngredients(of: pasta)
        #expect(added == 1)
        let entry = try #require(try store.shoppingItems().first)
        #expect(entry.name == "Parmesan Cheese")
        #expect(entry.reason == .recipe)
        #expect(entry.note == "Garlicky Chicken & Tomato Spaghetti")

        try store.addMissingIngredients(of: pasta)
        #expect(try store.shoppingItems().count == 1, "Adding twice doesn't duplicate")
    }

    @Test func cookingLogsUsageAndHistory() throws {
        let frittata = try evaluated(SampleRecipes.recipes[0])
        let eggsID = try #require(frittata.ingredients.first { $0.ingredient.name == "eggs" }?.itemID)
        let eggs = try #require(try store.item(id: eggsID))
        #expect(eggs.quantity == 0.5)

        try store.markCooked(frittata.recipe, uses: [(item: eggs, amount: 0.5)])

        #expect(eggs.status == .usedUp)
        let usage = try #require(try fetchAll(UsageEvent.self).first { $0.item?.id == eggsID && $0.date == Self.now })
        #expect(usage.type == .usedUp)
        let saved = try #require(try store.savedRecipe(id: frittata.recipe.id))
        #expect(saved.timesCooked == 1)
        #expect(saved.lastCookedAt == Self.now)
        #expect(!saved.isFavorite)
    }

    @Test func favoritesPersistWithoutPromptIDs() throws {
        var recipe = SampleRecipes.recipes[2]
        recipe.ingredients[0].inventoryItemId = "i7"
        try store.setFavorite(recipe, true)
        #expect(try store.isFavorite(recipe))

        let saved = try #require(try store.savedRecipe(id: recipe.id))
        let decoded = try #require(saved.recipe)
        #expect(decoded.title == recipe.title)
        let noPromptIDs = decoded.ingredients.allSatisfy { $0.inventoryItemId == nil }
        #expect(noPromptIDs)

        try store.setFavorite(recipe, false)
        #expect(try store.savedRecipe(id: recipe.id) == nil, "Never-cooked recipes are removed when unfavorited")
    }

    @Test func unfavoritingKeepsCookedHistory() throws {
        let recipe = SampleRecipes.recipes[3]
        try store.setFavorite(recipe, true)
        try store.markCooked(recipe, uses: [])
        try store.setFavorite(recipe, false)
        let saved = try #require(try store.savedRecipe(id: recipe.id))
        #expect(!saved.isFavorite)
        #expect(saved.timesCooked == 1)
    }

    @Test func mockServiceRecipesRankAgainstSampleInventory() async throws {
        let filters = RecipeFilters(maxMissing: 1)
        let request = try store.recipeRequest(filters: filters)
        let recipes = try await MockLLMService().suggestRecipes(request)
        let ranked = RecipeRanking.rank(
            recipes.map { IngredientMatcher.evaluate($0, items: request.items, assumeStaples: true) },
            filters: filters
        )
        let withinMissingLimit = ranked.allSatisfy { $0.missingCount <= 1 }
        #expect(withinMissingLimit)
        #expect(ranked.first?.expiringItemNames.isEmpty == false)
    }
}
