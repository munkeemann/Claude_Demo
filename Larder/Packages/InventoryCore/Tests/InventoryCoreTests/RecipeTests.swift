import Foundation
import Testing
@testable import InventoryCore

enum RecipeFixtures {
    /// The sample inventory as a recipe request, with fixed expiry offsets.
    static func sampleRequest(filters: RecipeFilters = RecipeFilters()) -> RecipeRequest {
        let items = SampleData.products.compactMap { product -> RecipeCandidate? in
            guard let stock = product.stock, product.category.defaultIsIngredient || product.category == .beverages else { return nil }
            return (UUID(), product.name, product.brand, product.category, product.unit.label(for: stock.quantity), stock.expiresInDays)
        }
        return RecipeRequest.build(items: items, filters: filters)
    }
}

struct RecipeRequestTests {
    @Test func ordersBySoonestExpiryAndAssignsShortIDs() {
        let request = RecipeFixtures.sampleRequest()
        #expect(request.items.first?.promptID == "i1")
        let days = request.items.compactMap(\.daysUntilExpiry)
        #expect(days == days.sorted())
        // Undated items come after dated ones.
        let firstUndated = request.items.firstIndex { $0.daysUntilExpiry == nil } ?? request.items.endIndex
        #expect(request.items[firstUndated...].allSatisfy { $0.daysUntilExpiry == nil })
    }

    @Test func capsTheInventoryList() {
        let many = (0..<200).map { index in
            (itemID: UUID(), name: "Item \(index)", brand: String?.none, category: ProductCategory.canned, amount: "1", daysUntilExpiry: Int?.none)
        }
        #expect(RecipeRequest.build(items: many, filters: RecipeFilters(), limit: 50).items.count == 50)
    }

    @Test func userMessageListsItemsAndFilters() {
        let filters = RecipeFilters(mealType: .dinner, maxMinutes: 30, maxMissing: 0, assumeStaples: true, count: 3, preferences: "vegetarian")
        let message = RecipePrompt.userMessage(for: RecipeFixtures.sampleRequest(filters: filters))
        #expect(message.contains("i1 | "))
        #expect(message.contains("Baby Spinach (Marketside) | 1 | in 1 day"))
        #expect(message.contains("Suggest 3 recipes."))
        #expect(message.contains("Meal type: dinner."))
        #expect(message.contains("at most 30 minutes"))
        #expect(message.contains("no missing ingredients"))
        #expect(message.contains("Assume these staples"))
        #expect(message.contains("Preferences: vegetarian"))
    }

    @Test func expiredItemsAreLabeled() {
        let request = RecipeRequest.build(
            items: [(UUID(), "Old Yogurt", nil, .dairy, "1", -2)],
            filters: RecipeFilters(maxMissing: 2, assumeStaples: false)
        )
        let message = RecipePrompt.userMessage(for: request)
        #expect(message.contains("expired 2 days ago"))
        #expect(message.contains("At most 2 missing"))
        #expect(message.contains("Do not assume any staples"))
    }

    @Test func schemaFollowsStructuredOutputRules() {
        func check(_ schema: JSONValue) {
            guard let object = schema.objectValue else { return }
            if object["type"] == "object" {
                #expect(object["additionalProperties"] == false)
                let properties = object["properties"]?.objectValue ?? [:]
                let required = Set(object["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
                #expect(required == Set(properties.keys))
                properties.values.forEach(check)
            }
            if let items = object["items"] { check(items) }
            object["anyOf"]?.arrayValue?.forEach(check)
        }
        check(RecipePrompt.schema)
    }
}

struct RecipeDecodingTests {
    @Test func sampleRecipesDecode() {
        let recipes = SampleRecipes.recipes
        #expect(recipes.count == 4)
        #expect(Set(recipes.map(\.id)).count == 4, "Each decoded recipe gets its own id")
        #expect(recipes[0].mealType == .breakfast)
        #expect(recipes[0].ingredients.count == 7)
    }

    @Test func decodingIsLenient() throws {
        let json = """
        {"recipes": [{"title": "Toast", "mealType": "brunch", "ingredients": [{"name": "bread", "inventoryItemId": ""}]}]}
        """
        let recipe = try #require(try JSONDecoder().decode(RecipeResponse.self, from: Data(json.utf8)).recipes.first)
        #expect(recipe.mealType == .any)
        #expect(recipe.servings == 2)
        #expect(recipe.steps.isEmpty)
        #expect(recipe.ingredients.first?.inventoryItemId == nil)
        #expect(recipe.ingredients.first?.amount == "")
    }

    @Test func stripsInventoryReferencesForSaving() {
        var recipe = SampleRecipes.recipes[0]
        recipe.ingredients[0].inventoryItemId = "i2"
        #expect(recipe.withoutInventoryReferences.ingredients.allSatisfy { $0.inventoryItemId == nil })
        #expect(recipe.withoutInventoryReferences.id == recipe.id)
    }

    @Test func savedRecipesRoundTripWithTheirID() throws {
        let original = SampleRecipes.recipes[1]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Recipe.self, from: data)
        #expect(decoded == original)
    }
}

struct IngredientMatcherTests {
    let spinach = RecipeInventoryItem(promptID: "i1", itemID: UUID(), name: "Baby Spinach", category: .produce, amount: "1 bag", daysUntilExpiry: 1)
    let eggs = RecipeInventoryItem(promptID: "i2", itemID: UUID(), name: "Large Eggs", category: .eggs, amount: "0.5 dozen", daysUntilExpiry: 23)
    let cheddar = RecipeInventoryItem(promptID: "i3", itemID: UUID(), name: "Sharp Cheddar Cheese", category: .cheese, amount: "5 oz", daysUntilExpiry: 21)
    let spaghetti = RecipeInventoryItem(promptID: "i4", itemID: UUID(), name: "Spaghetti", category: .grains, amount: "2 boxes")
    let tomatoes = RecipeInventoryItem(promptID: "i5", itemID: UUID(), name: "Roma Tomatoes", category: .produce, amount: "4", daysUntilExpiry: 3)

    var items: [RecipeInventoryItem] { [spinach, eggs, cheddar, spaghetti, tomatoes] }

    func recipe(_ ingredients: [RecipeIngredient]) -> Recipe {
        Recipe(title: "Test", summary: "", mealType: .dinner, totalMinutes: 20, servings: 2, ingredients: ingredients, steps: [])
    }

    @Test(arguments: [
        ("eggs", true),
        ("baby spinach", true),
        ("fresh spinach", true),
        ("cheddar cheese", true),
        ("sharp cheddar", true),
        ("roma tomato", true),
        ("tomatoes", true),
        ("parmesan cheese", false),
        ("chicken broth", false),
        ("spaghetti squash", false),
    ])
    func nameMatching(ingredient: String, expected: Bool) {
        let evaluated = IngredientMatcher.evaluate(recipe([RecipeIngredient(name: ingredient, amount: "1")]), items: items, assumeStaples: true)
        #expect((evaluated.ingredients[0].itemID != nil) == expected, "\(ingredient)")
    }

    @Test func validItemIDsAreTrusted() {
        let pasta = RecipeIngredient(name: "pasta", amount: "8 oz", inventoryItemId: "i4", have: true)
        let evaluated = IngredientMatcher.evaluate(recipe([pasta]), items: items, assumeStaples: true)
        #expect(evaluated.ingredients[0].itemID == spaghetti.itemID)
    }

    @Test func claimedHaveWithoutAMatchIsMissing() {
        let invented = RecipeIngredient(name: "saffron", amount: "a pinch", inventoryItemId: "i99", have: true)
        let evaluated = IngredientMatcher.evaluate(recipe([invented]), items: items, assumeStaples: true)
        #expect(evaluated.ingredients[0].availability == .missing)
        #expect(evaluated.missingCount == 1)
    }

    @Test func staplesDependOnTheFilter() {
        let salt = RecipeIngredient(name: "salt", amount: "to taste", isStaple: true)
        #expect(IngredientMatcher.evaluate(recipe([salt]), items: items, assumeStaples: true).ingredients[0].availability == .staple)
        #expect(IngredientMatcher.evaluate(recipe([salt]), items: items, assumeStaples: false).ingredients[0].availability == .missing)
    }

    @Test func reportsExpiringItemsUsed() {
        let evaluated = IngredientMatcher.evaluate(
            recipe([
                RecipeIngredient(name: "spinach", amount: "2 cups"),
                RecipeIngredient(name: "tomatoes", amount: "2"),
                RecipeIngredient(name: "eggs", amount: "4"),
            ]),
            items: items,
            assumeStaples: true
        )
        #expect(evaluated.expiringItemNames == ["Baby Spinach", "Roma Tomatoes"])
        #expect(evaluated.usedItemIDs.count == 3)
    }

    @Test func sampleRecipesMatchSampleInventory() {
        let request = RecipeFixtures.sampleRequest()
        let frittata = IngredientMatcher.evaluate(SampleRecipes.recipes[0], items: request.items, assumeStaples: true)
        #expect(frittata.missingCount == 0)
        #expect(frittata.expiringItemNames.contains("Baby Spinach"))
        let pasta = IngredientMatcher.evaluate(SampleRecipes.recipes[1], items: request.items, assumeStaples: true)
        #expect(pasta.missing.map(\.ingredient.name) == ["parmesan cheese"])
    }
}

struct RecipeRankingTests {
    func evaluated(_ title: String, minutes: Int, missing: Int, expiring: [String]) -> EvaluatedRecipe {
        let ingredients = (0..<missing).map {
            EvaluatedIngredient(ingredient: RecipeIngredient(name: "m\($0)", amount: "1"), availability: .missing)
        }
        let recipe = Recipe(title: title, summary: "", mealType: .dinner, totalMinutes: minutes, servings: 2, ingredients: [], steps: [])
        return EvaluatedRecipe(recipe: recipe, ingredients: ingredients, expiringItemNames: expiring)
    }

    @Test func filtersByMissingAndTime() {
        let recipes = [
            evaluated("OK", minutes: 20, missing: 1, expiring: []),
            evaluated("Too many missing", minutes: 20, missing: 3, expiring: []),
            evaluated("Too slow", minutes: 90, missing: 0, expiring: []),
            evaluated("Unknown time", minutes: 0, missing: 0, expiring: []),
        ]
        let ranked = RecipeRanking.rank(recipes, filters: RecipeFilters(maxMinutes: 45, maxMissing: 2))
        #expect(Set(ranked.map(\.recipe.title)) == ["OK", "Unknown time"])
    }

    @Test func onlyWhatIHaveMeansZeroMissing() {
        let ranked = RecipeRanking.rank(
            [evaluated("A", minutes: 10, missing: 1, expiring: []), evaluated("B", minutes: 10, missing: 0, expiring: [])],
            filters: RecipeFilters(maxMissing: 0)
        )
        #expect(ranked.map(\.recipe.title) == ["B"])
    }

    @Test func expiringFirstThenFewestMissingThenFastest() {
        let ranked = RecipeRanking.rank(
            [
                evaluated("Slow", minutes: 40, missing: 0, expiring: []),
                evaluated("Fast", minutes: 10, missing: 0, expiring: []),
                evaluated("Missing one", minutes: 5, missing: 1, expiring: []),
                evaluated("Rescues two", minutes: 45, missing: 2, expiring: ["a", "b"]),
                evaluated("Rescues one", minutes: 30, missing: 0, expiring: ["a"]),
            ],
            filters: RecipeFilters(maxMissing: 2)
        )
        #expect(ranked.map(\.recipe.title) == ["Rescues two", "Rescues one", "Fast", "Slow", "Missing one"])
    }
}

struct CookedUsagePlannerTests {
    @Test(arguments: [
        ("2 cups", ItemState(quantity: 1, initialQuantity: 1, unit: .gallon, status: .inStock), 0.13),
        ("1/4 cup", ItemState(quantity: 0.6, initialQuantity: 1, unit: .gallon, status: .inStock), 0.02),
        ("6", ItemState(quantity: 1, initialQuantity: 1, unit: .dozen, status: .inStock), 0.5),
        ("1 1/2 lb", ItemState(quantity: 2.1, initialQuantity: 2.1, unit: .pound, status: .inStock), 1.5),
        ("8 oz", ItemState(quantity: 2.1, initialQuantity: 2.1, unit: .pound, status: .inStock), 0.5),
        ("1 can", ItemState(quantity: 3, initialQuantity: 4, unit: .can, status: .inStock), 1),
        ("3 cloves", ItemState(quantity: 2, initialQuantity: 3, unit: .each, status: .inStock), 2),
        ("3 lb", ItemState(quantity: 2.1, initialQuantity: 2.1, unit: .pound, status: .inStock), 2.1),
        ("a pinch", ItemState(quantity: 4, initialQuantity: 6, unit: .each, status: .inStock), 1),
        ("2 cups", ItemState(quantity: 12, initialQuantity: 32, unit: .ounce, status: .inStock), 8),
        ("½ cup", ItemState(quantity: 1, initialQuantity: 1, unit: .gallon, status: .inStock), 0.03),
    ])
    func amounts(recipeAmount: String, item: ItemState, expected: Double) {
        let amount = CookedUsagePlanner.suggestedAmount(recipeAmount: recipeAmount, item: item)
        #expect(abs(amount - expected) < 0.001, "\(recipeAmount) → \(amount)")
    }

    @Test func nothingLeftMeansNothingUsed() {
        let empty = ItemState(quantity: 0, initialQuantity: 1, unit: .gallon, status: .usedUp)
        #expect(CookedUsagePlanner.suggestedAmount(recipeAmount: "1 cup", item: empty) == 0)
    }
}

struct RecipeServiceTests {
    @Test func anthropicServiceSendsRecipeSchema() async throws {
        let http = ScriptedHTTPClient([.respond(status: 200, body: MessagesFixtures.success(text: SampleRecipes.json))])
        let client = AnthropicClient(http: http, sleep: { _ in }, apiKey: { "sk-ant-test" })
        let service = AnthropicLLMService(client: client, model: { .opus5 })

        let recipes = try await service.suggestRecipes(RecipeFixtures.sampleRequest())
        #expect(recipes.map(\.title) == SampleRecipes.recipes.map(\.title))

        let body = try http.body(at: 0)
        #expect(body["system"]?.stringValue == RecipePrompt.system)
        #expect(body["output_config"]?["format"]?["schema"] == RecipePrompt.schema)
        #expect(body["messages"]?.arrayValue?.first?["content"]?.stringValue?.contains("Baby Spinach") == true)
    }

    @Test func emptyInventorySkipsTheCall() async throws {
        let http = ScriptedHTTPClient([])
        let client = AnthropicClient(http: http, sleep: { _ in }, apiKey: { "sk-ant-test" })
        let service = AnthropicLLMService(client: client, model: { .opus5 })
        let recipes = try await service.suggestRecipes(RecipeRequest(items: [], filters: RecipeFilters()))
        #expect(recipes.isEmpty)
        #expect(http.requestCount == 0)
    }
}
