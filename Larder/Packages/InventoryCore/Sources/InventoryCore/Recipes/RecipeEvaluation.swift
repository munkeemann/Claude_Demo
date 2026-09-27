import Foundation

/// Where a recipe ingredient comes from, decided locally rather than trusting
/// the model's `have` flag.
public enum IngredientAvailability: Sendable, Hashable {
    case inInventory(itemID: UUID)
    case staple
    case missing
}

public struct EvaluatedIngredient: Sendable, Hashable {
    public var ingredient: RecipeIngredient
    public var availability: IngredientAvailability

    public var isMissing: Bool { availability == .missing }

    public var itemID: UUID? {
        if case .inInventory(let id) = availability { return id }
        return nil
    }
}

public struct EvaluatedRecipe: Sendable, Hashable, Identifiable {
    public var recipe: Recipe
    public var ingredients: [EvaluatedIngredient]
    /// Names of matched inventory items that expire within the "soon" window.
    public var expiringItemNames: [String]

    public var id: UUID { recipe.id }
    public var missing: [EvaluatedIngredient] { ingredients.filter(\.isMissing) }
    public var missingCount: Int { missing.count }
    public var usedItemIDs: [UUID] { ingredients.compactMap(\.itemID) }
}

/// Matches recipe ingredients against inventory items.
///
/// An ingredient counts as "in inventory" if Claude referenced an item id
/// that exists in the request, or if its name matches an item by words
/// (plurals folded, descriptors like "fresh" ignored). Claude's own `have`
/// flag is never trusted on its own. Staples count as available only when
/// the user said to assume them.
public enum IngredientMatcher {
    static let ignoredWords: Set<String> = [
        "fresh", "large", "small", "medium", "whole", "chopped", "diced", "sliced", "minced", "organic",
        "boneless", "skinless", "extra", "virgin", "plain", "ripe", "dried", "ground", "raw", "cooked",
        "of", "and", "or", "a", "the", "to", "taste", "for", "cup", "cups", "lb", "oz",
    ]

    public static func evaluate(
        _ recipe: Recipe,
        items: [RecipeInventoryItem],
        assumeStaples: Bool,
        expiringWithinDays soonDays: Int = 3
    ) -> EvaluatedRecipe {
        let byPromptID = Dictionary(items.map { ($0.promptID, $0) }, uniquingKeysWith: { first, _ in first })
        var expiring: [String] = []

        let evaluated = recipe.ingredients.map { ingredient -> EvaluatedIngredient in
            let match: RecipeInventoryItem?
            if let id = ingredient.inventoryItemId, let item = byPromptID[id] {
                match = item
            } else {
                match = items.first { namesMatch(ingredient.name, $0.name) }
            }
            if let match {
                if let days = match.daysUntilExpiry, (0...soonDays).contains(days), !expiring.contains(match.name) {
                    expiring.append(match.name)
                }
                return EvaluatedIngredient(ingredient: ingredient, availability: .inInventory(itemID: match.itemID))
            }
            if ingredient.isStaple && assumeStaples {
                return EvaluatedIngredient(ingredient: ingredient, availability: .staple)
            }
            return EvaluatedIngredient(ingredient: ingredient, availability: .missing)
        }
        return EvaluatedRecipe(recipe: recipe, ingredients: evaluated, expiringItemNames: expiring)
    }

    /// Words that name a part or form of an ingredient rather than a
    /// different food: "garlic cloves" is still garlic.
    static let formWords: Set<String> = [
        "clove", "leaf", "slice", "floret", "sprig", "stalk", "piece", "juice", "zest", "wedge",
        "chunk", "cube", "strip", "fillet", "breast", "thigh", "head", "bunch",
    ]

    /// An ingredient matches an item when its words are a subset of the
    /// item's ("eggs" ~ "Large Eggs", "cheddar cheese" ~ "Sharp Cheddar
    /// Cheese"), or when it only adds form words ("garlic cloves" ~ "Garlic").
    /// "spaghetti squash" is not "Spaghetti"; "parmesan cheese" is not
    /// "Sharp Cheddar Cheese".
    static func namesMatch(_ ingredient: String, _ item: String) -> Bool {
        let ingredientWords = words(ingredient)
        let itemWords = words(item)
        guard !ingredientWords.isEmpty, !itemWords.isEmpty else { return false }
        if ingredientWords.isSubset(of: itemWords) { return true }
        if itemWords.isSubset(of: ingredientWords) {
            return ingredientWords.subtracting(itemWords).isSubset(of: formWords)
        }
        return false
    }

    static func words(_ text: String) -> Set<String> {
        Set(
            TextNormalizer.tokens(text)
                .filter { !ignoredWords.contains($0) && !$0.allSatisfy(\.isNumber) }
                .map(singular)
        )
    }

    /// Folds simple English plurals: "tomatoes" → "tomato", "eggs" → "egg",
    /// "berries" → "berry". Words ending in "ss" are left alone.
    static func singular(_ word: String) -> String {
        guard word.count > 3, !word.hasSuffix("ss") else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") || word.hasSuffix("ches") || word.hasSuffix("shes") { return String(word.dropLast(2)) }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }
}

public enum RecipeRanking {
    /// Applies the filters locally (Claude may drift) and orders recipes so
    /// those rescuing expiring items and needing fewer purchases come first.
    public static func rank(_ recipes: [EvaluatedRecipe], filters: RecipeFilters) -> [EvaluatedRecipe] {
        recipes
            .filter { $0.missingCount <= filters.maxMissing }
            .filter { recipe in
                guard let maxMinutes = filters.maxMinutes, recipe.recipe.totalMinutes > 0 else { return true }
                return recipe.recipe.totalMinutes <= maxMinutes
            }
            .sorted { lhs, rhs in
                if lhs.expiringItemNames.count != rhs.expiringItemNames.count {
                    return lhs.expiringItemNames.count > rhs.expiringItemNames.count
                }
                if lhs.missingCount != rhs.missingCount { return lhs.missingCount < rhs.missingCount }
                return lhs.recipe.totalMinutes < rhs.recipe.totalMinutes
            }
    }
}

/// Suggests how much of each inventory item cooking a recipe uses.
public enum CookedUsagePlanner {
    /// Parses the recipe amount and converts it to the item's unit when
    /// possible; otherwise uses one unit for discrete items or a quarter of
    /// the original amount. Always capped at what's left.
    public static func suggestedAmount(recipeAmount: String, item: ItemState) -> Double {
        let remaining = max(0, item.quantity)
        guard remaining > 0 else { return 0 }
        if let quantity = parse(recipeAmount) {
            // Includes "3" eggs against an item counted in dozens.
            if let converted = quantity.unit.convert(quantity.value, to: item.unit) {
                return min(remaining, rounded(converted))
            }
            // "2 cloves" of garlic against a count of bulbs, "1" against cans, etc.
            if quantity.unit == .each, item.unit.isDiscrete {
                return min(remaining, rounded(quantity.value))
            }
        }
        return QuickActionCalculator.suggestedUseAmount(for: item)
    }

    /// "2 cups" → 2 cup; "3" / "3 large" → 3 each; "1/2 lb" → 0.5 lb.
    static func parse(_ text: String) -> Quantity? {
        let lowered = text.lowercased().replacingOccurrences(of: "½", with: "1/2").replacingOccurrences(of: "¼", with: "1/4")
        let tokens = lowered.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        guard let first = tokens.first else { return nil }

        var value: Double?
        var nextIndex = 1
        if let fraction = parseFraction(first) {
            value = fraction
            // "1 1/2 cups"
            if tokens.count > 1, let extra = parseFraction(tokens[1]), tokens[1].contains("/") {
                value = fraction + extra
                nextIndex = 2
            }
        } else if let size = PackageSize.parse(first), let unitSize = size.unitSize {
            return unitSize
        }
        guard let value, value > 0 else { return nil }

        let rest = tokens.dropFirst(nextIndex)
        if rest.count >= 2, let unit = PackageSize.unit(for: rest.prefix(2).joined(separator: " ")) {
            return Quantity(value, unit)
        }
        if let word = rest.first, let unit = PackageSize.unit(for: word) {
            return Quantity(value, unit)
        }
        return Quantity(value, .each)
    }

    static func parseFraction(_ token: String) -> Double? {
        let parts = token.split(separator: "/")
        if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 {
            return numerator / denominator
        }
        return Double(token)
    }

    static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
