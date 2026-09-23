import Foundation

public enum RecipePrompt {
    public static let staples = "salt, black pepper, cooking oil, water, sugar, all-purpose flour, and common dried spices"

    /// Stable instructions; the inventory and filters go in the user message.
    public static let system = """
    You suggest home-cooking recipes built around what a household already has. You receive their \
    current food inventory, each item with a short id (like "i3") and, when known, the days until it \
    expires.

    Rules:
    - Prioritize ingredients that expire soonest; a recipe that rescues items about to spoil is better \
    than one that ignores them. Already-expired items (negative days) should not be used.
    - Stay within the requested meal type, total time, and number of missing ingredients.
    - Every ingredient line: name (plain, e.g. "baby spinach"), amount (e.g. "2 cups", "1 lb", \
    "3 cloves").
    - If an ingredient comes from the inventory, set inventoryItemId to that item's id and have to true. \
    Use each id only for an item that truly matches.
    - Mark basic staples with isStaple true. When staples are assumed, they don't count as missing.
    - Anything else the household lacks: have false, inventoryItemId null. Keep these few and common.
    - totalMinutes includes prep and cooking. Steps are short, imperative, and in order.
    - Suggest genuinely different dishes, and respect any stated preferences or restrictions.
    """

    public static func userMessage(for request: RecipeRequest) -> String {
        var lines: [String] = []
        lines.append("Inventory (id | item | amount | expires):")
        for item in request.items {
            let brand = item.brand.map { " (\($0))" } ?? ""
            let expiry: String
            switch item.daysUntilExpiry {
            case nil: expiry = "not tracked"
            case let days? where days < 0: expiry = "expired \(-days) days ago"
            case 0?: expiry = "today"
            case 1?: expiry = "in 1 day"
            case let days?: expiry = "in \(days) days"
            }
            lines.append("\(item.promptID) | \(item.name)\(brand) | \(item.amount) | \(expiry)")
        }

        let filters = request.filters
        var requirements: [String] = []
        requirements.append("Suggest \(filters.count) recipes.")
        if filters.mealType != .any {
            requirements.append("Meal type: \(filters.mealType.rawValue).")
        }
        if let maxMinutes = filters.maxMinutes {
            requirements.append("Total time: at most \(maxMinutes) minutes.")
        }
        if filters.maxMissing == 0 {
            requirements.append("Use only what the household has: no missing ingredients.")
        } else {
            requirements.append("At most \(filters.maxMissing) missing ingredients per recipe.")
        }
        if filters.assumeStaples {
            requirements.append("Assume these staples are on hand: \(staples).")
        } else {
            requirements.append("Do not assume any staples; anything not in the inventory counts as missing.")
        }
        let preferences = filters.preferences.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferences.isEmpty {
            requirements.append("Preferences: \(preferences)")
        }
        return lines.joined(separator: "\n") + "\n\n" + requirements.joined(separator: "\n")
    }

    public static let schema: JSONValue = JSONSchema.object([
        ("recipes", JSONSchema.array(of: recipeSchema)),
    ])

    static let recipeSchema: JSONValue = JSONSchema.object([
        ("title", JSONSchema.string()),
        ("summary", JSONSchema.string("One sentence on what it is and why it fits.")),
        ("mealType", JSONSchema.enumeration(MealType.allCases.map(\.rawValue))),
        ("totalMinutes", JSONSchema.integer()),
        ("servings", JSONSchema.integer()),
        ("ingredients", JSONSchema.array(of: JSONSchema.object([
            ("name", JSONSchema.string()),
            ("amount", JSONSchema.string()),
            ("inventoryItemId", JSONSchema.nullable(JSONSchema.string("Inventory id like \"i3\" when this comes from the inventory."))),
            ("have", JSONSchema.boolean()),
            ("isStaple", JSONSchema.boolean()),
        ]))),
        ("steps", JSONSchema.array(of: JSONSchema.string())),
    ])
}
