/// Product categories. Raw values are persisted and are also the enum values
/// in the LLM extraction schemas, so treat them as stable identifiers.
public enum ProductCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    // Food
    case produce
    case meat
    case seafood
    case dairy
    case cheese
    case eggs
    case bakery
    case deli
    case frozen
    case grains
    case canned
    case condiments
    case spices
    case snacks
    case beverages
    case leftovers
    // Household
    case cleaning
    case paperGoods
    case laundry
    case personalCare
    case health
    case baby
    case pet
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .produce: "Produce"
        case .meat: "Meat & Poultry"
        case .seafood: "Seafood"
        case .dairy: "Dairy"
        case .cheese: "Cheese"
        case .eggs: "Eggs"
        case .bakery: "Bakery"
        case .deli: "Deli"
        case .frozen: "Frozen Foods"
        case .grains: "Grains & Pasta"
        case .canned: "Canned & Jarred"
        case .condiments: "Condiments & Sauces"
        case .spices: "Spices & Baking"
        case .snacks: "Snacks"
        case .beverages: "Beverages"
        case .leftovers: "Leftovers"
        case .cleaning: "Cleaning"
        case .paperGoods: "Paper Goods"
        case .laundry: "Laundry"
        case .personalCare: "Personal Care"
        case .health: "Health"
        case .baby: "Baby"
        case .pet: "Pet"
        case .other: "Other"
        }
    }

    public var systemImage: String {
        switch self {
        case .produce: "carrot"
        case .meat: "fork.knife"
        case .seafood: "fish"
        case .dairy: "drop"
        case .cheese: "triangle"
        case .eggs: "oval"
        case .bakery: "birthday.cake"
        case .deli: "takeoutbag.and.cup.and.straw"
        case .frozen: "snowflake"
        case .grains: "bag"
        case .canned: "cylinder"
        case .condiments: "drop.triangle"
        case .spices: "leaf"
        case .snacks: "popcorn"
        case .beverages: "cup.and.saucer"
        case .leftovers: "takeoutbag.and.cup.and.straw"
        case .cleaning: "bubbles.and.sparkles"
        case .paperGoods: "scroll"
        case .laundry: "washer"
        case .personalCare: "hands.sparkles"
        case .health: "cross.case"
        case .baby: "stroller"
        case .pet: "pawprint"
        case .other: "shippingbox"
        }
    }

    public var isFood: Bool {
        switch self {
        case .produce, .meat, .seafood, .dairy, .cheese, .eggs, .bakery, .deli, .frozen,
             .grains, .canned, .condiments, .spices, .snacks, .beverages, .leftovers:
            true
        case .cleaning, .paperGoods, .laundry, .personalCare, .health, .baby, .pet, .other:
            false
        }
    }

    /// Whether products in this category are offered to recipe suggestions by default.
    public var defaultIsIngredient: Bool {
        isFood && self != .snacks && self != .beverages
    }

    /// Whether products in this category are perishable enough to track expiry by default.
    public var defaultTracksExpiry: Bool {
        switch self {
        case .produce, .meat, .seafood, .dairy, .cheese, .eggs, .bakery, .deli, .frozen, .leftovers:
            true
        default:
            false
        }
    }

    /// Whether to forecast when the household runs out. Leftovers are one-offs.
    public var defaultTracksRunOut: Bool { self != .leftovers }

    public var defaultClimate: StorageClimate {
        switch self {
        case .produce, .meat, .seafood, .dairy, .cheese, .eggs, .deli, .leftovers: .fridge
        case .frozen: .freezer
        default: .room
        }
    }

    public var defaultLocationKind: LocationKind {
        switch self {
        case .produce, .meat, .seafood, .dairy, .cheese, .eggs, .deli, .leftovers: .fridge
        case .frozen: .freezer
        case .cleaning, .laundry: .cleaning
        case .personalCare, .health, .baby: .bathroom
        default: .pantry
        }
    }

    public var defaultUnit: MeasureUnit {
        switch self {
        case .meat, .seafood: .pound
        case .eggs: .dozen
        case .paperGoods: .pack
        default: .each
        }
    }

    public static let foodCategories = allCases.filter(\.isFood)
    public static let householdCategories = allCases.filter { !$0.isFood }
}
