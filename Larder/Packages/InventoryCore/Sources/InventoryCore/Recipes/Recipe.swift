import Foundation

public enum MealType: String, Codable, CaseIterable, Sendable, Identifiable {
    case any
    case breakfast
    case lunch
    case dinner
    case snack
    case dessert

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .any: "Any meal"
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        case .dessert: "Dessert"
        }
    }
}

/// A recipe as returned by Claude (and as saved to favorites).
public struct Recipe: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var mealType: MealType
    public var totalMinutes: Int
    public var servings: Int
    public var ingredients: [RecipeIngredient]
    public var steps: [String]

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        mealType: MealType,
        totalMinutes: Int,
        servings: Int,
        ingredients: [RecipeIngredient],
        steps: [String]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.mealType = mealType
        self.totalMinutes = totalMinutes
        self.servings = servings
        self.ingredients = ingredients
        self.steps = steps
    }

    /// The recipe with prompt-specific item ids removed. Saved recipes are
    /// re-matched by ingredient name, because "i3" means a different item
    /// in every request.
    public var withoutInventoryReferences: Recipe {
        var copy = self
        copy.ingredients = ingredients.map { ingredient in
            var cleared = ingredient
            cleared.inventoryItemId = nil
            return cleared
        }
        return copy
    }

    enum CodingKeys: String, CodingKey {
        case id, title, summary, mealType, totalMinutes, servings, ingredients, steps
    }

    /// Claude's JSON has no `id`; one is assigned on decode. Unknown meal
    /// types and missing numbers degrade gracefully.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        summary = (try? container.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        mealType = (try? container.decode(MealType.self, forKey: .mealType)) ?? .any
        totalMinutes = max(0, (try? container.decode(Int.self, forKey: .totalMinutes)) ?? 0)
        servings = max(1, (try? container.decode(Int.self, forKey: .servings)) ?? 2)
        ingredients = try container.decode([RecipeIngredient].self, forKey: .ingredients)
        steps = (try? container.decode([String].self, forKey: .steps)) ?? []
    }
}

public struct RecipeIngredient: Codable, Sendable, Hashable {
    public var name: String
    /// Free-text amount, e.g. "2 cups", "1 lb", "a pinch".
    public var amount: String
    /// The request's short item ID ("i3") when the recipe uses that item.
    public var inventoryItemId: String?
    /// Claude's claim that the household has it (re-checked locally).
    public var have: Bool
    /// Salt, oil and the like, assumed on hand.
    public var isStaple: Bool

    public init(name: String, amount: String, inventoryItemId: String? = nil, have: Bool = false, isStaple: Bool = false) {
        self.name = name
        self.amount = amount
        self.inventoryItemId = inventoryItemId
        self.have = have
        self.isStaple = isStaple
    }

    enum CodingKeys: String, CodingKey {
        case name, amount, inventoryItemId, have, isStaple
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        amount = (try? container.decodeIfPresent(String.self, forKey: .amount)) ?? ""
        inventoryItemId = (try? container.decodeIfPresent(String.self, forKey: .inventoryItemId)).flatMap { $0.isEmpty ? nil : $0 }
        have = (try? container.decode(Bool.self, forKey: .have)) ?? false
        isStaple = (try? container.decode(Bool.self, forKey: .isStaple)) ?? false
    }
}

public struct RecipeFilters: Sendable, Equatable {
    public var mealType: MealType
    /// nil means no limit.
    public var maxMinutes: Int?
    /// Missing ingredients allowed, not counting staples. 0 = only what I have.
    public var maxMissing: Int
    public var assumeStaples: Bool
    public var count: Int
    /// Free-text preferences ("vegetarian", "no peanuts", "kid friendly").
    public var preferences: String

    public init(
        mealType: MealType = .any,
        maxMinutes: Int? = nil,
        maxMissing: Int = 2,
        assumeStaples: Bool = true,
        count: Int = 4,
        preferences: String = ""
    ) {
        self.mealType = mealType
        self.maxMinutes = maxMinutes
        self.maxMissing = maxMissing
        self.assumeStaples = assumeStaples
        self.count = count
        self.preferences = preferences
    }
}

/// One inventory item as offered to Claude.
public struct RecipeInventoryItem: Sendable, Equatable {
    /// Short ID used in the prompt ("i1").
    public var promptID: String
    /// The app's item ID.
    public var itemID: UUID
    public var name: String
    public var brand: String?
    public var category: ProductCategory
    public var amount: String
    /// Calendar days until expiry; negative if already expired.
    public var daysUntilExpiry: Int?

    public init(promptID: String, itemID: UUID, name: String, brand: String? = nil, category: ProductCategory, amount: String, daysUntilExpiry: Int? = nil) {
        self.promptID = promptID
        self.itemID = itemID
        self.name = name
        self.brand = brand
        self.category = category
        self.amount = amount
        self.daysUntilExpiry = daysUntilExpiry
    }
}

/// An in-stock item that could go into a recipe request.
public typealias RecipeCandidate = (
    itemID: UUID,
    name: String,
    brand: String?,
    category: ProductCategory,
    amount: String,
    daysUntilExpiry: Int?
)

public struct RecipeRequest: Sendable, Equatable {
    public var items: [RecipeInventoryItem]
    public var filters: RecipeFilters

    public init(items: [RecipeInventoryItem], filters: RecipeFilters) {
        self.items = items
        self.filters = filters
    }

    /// Orders items so the soonest-expiring come first, assigns short IDs,
    /// and caps the list to keep the prompt small.
    public static func build(
        items: [RecipeCandidate],
        filters: RecipeFilters,
        limit: Int = 80
    ) -> RecipeRequest {
        let sorted = items.sorted { lhs, rhs in
            switch (lhs.daysUntilExpiry, rhs.daysUntilExpiry) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
        let entries = sorted.prefix(limit).enumerated().map { index, item in
            RecipeInventoryItem(
                promptID: "i\(index + 1)",
                itemID: item.itemID,
                name: item.name,
                brand: item.brand,
                category: item.category,
                amount: item.amount,
                daysUntilExpiry: item.daysUntilExpiry
            )
        }
        return RecipeRequest(items: entries, filters: filters)
    }
}

struct RecipeResponse: Codable {
    var recipes: [Recipe]
}
