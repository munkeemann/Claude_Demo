/// Maps Open*Facts `categories_tags` (and, for household goods, the product
/// name) to a `ProductCategory`.
///
/// Tags are matched exactly after dropping the language prefix. Substring
/// matching is wrong here: nearly every plant food carries
/// "en:plant-based-foods-and-beverages", which would read as a beverage.
/// Rules are checked in order, so the more specific categories come first
/// (frozen pizza is frozen, canned tuna is canned, butter is dairy).
enum OpenFactsCategoryMapper {
    static let tagRules: [(ProductCategory, Set<String>)] = [
        (.frozen, ["frozen-foods", "frozen-desserts", "ice-creams", "frozen-vegetables", "frozen-fruits", "frozen-pizzas", "frozen-meals"]),
        (.cheese, ["cheeses"]),
        (.eggs, ["eggs", "chicken-eggs"]),
        (.dairy, ["milks", "dairies", "yogurts", "butters", "creams", "fermented-milk-products", "dairy-desserts", "plant-based-milks", "milk-substitutes"]),
        (.beverages, ["beverages", "waters", "sodas", "juices", "fruit-juices", "coffees", "teas", "alcoholic-beverages", "wines", "beers", "energy-drinks"]),
        (.canned, ["canned-foods", "canned-vegetables", "canned-fruits", "canned-fishes", "canned-meats", "canned-legumes", "canned-soups", "soups"]),
        (.deli, ["prepared-meats", "hams", "salamis", "cold-cuts", "hummus"]),
        (.meat, ["meats", "poultries", "chickens", "beef", "pork", "sausages", "ground-meats", "turkeys"]),
        (.seafood, ["seafood", "fishes", "fishes-and-their-products", "shrimps", "salmons", "tunas"]),
        (.condiments, ["condiments", "sauces", "spreads", "sweet-spreads", "jams", "honeys", "vegetable-oils", "olive-oils", "vinegars", "mayonnaises", "ketchup", "mustards", "salad-dressings", "nut-butters", "peanut-butters"]),
        (.spices, ["spices", "salts", "sugars", "baking-powders", "yeasts", "dried-herbs", "seasonings"]),
        (.snacks, ["snacks", "sweet-snacks", "salty-snacks", "crisps", "chips", "biscuits", "cookies", "chocolates", "candies", "confectioneries", "crackers", "nuts", "popcorn", "cereal-bars"]),
        (.bakery, ["breads", "sliced-breads", "pastries", "cakes", "viennoiseries", "tortillas", "bagels"]),
        (.grains, ["pastas", "rices", "flours", "breakfast-cereals", "noodles", "cereal-grains", "oats", "dried-legumes", "cereals-and-their-products"]),
        (.produce, ["fresh-vegetables", "fresh-fruits", "fruits", "vegetables", "salads", "leafy-vegetables", "potatoes", "fresh-herbs", "mushrooms", "root-vegetables", "tomatoes", "bananas", "apples"]),
    ]

    /// Household goods rarely have useful tags; match on the name instead.
    static let nameRules: [(ProductCategory, [String])] = [
        (.baby, ["diaper", "baby wipes", "infant formula"]),
        (.pet, ["dog food", "cat food", "cat litter", "dog treats", "cat treats"]),
        (.laundry, ["laundry", "fabric softener", "dryer sheet", "stain remover"]),
        (.paperGoods, ["toilet paper", "bath tissue", "paper towel", "facial tissue", "tissues", "napkins"]),
        (.cleaning, ["dish soap", "dishwasher", "dish detergent", "cleaner", "bleach", "disinfect", "wipes", "sponge", "trash bag", "garbage bag"]),
        (.personalCare, ["shampoo", "conditioner", "toothpaste", "toothbrush", "deodorant", "body wash", "hand soap", "bar soap", "lotion", "razor", "floss", "mouthwash", "sunscreen"]),
        (.health, ["vitamin", "ibuprofen", "acetaminophen", "bandage", "allergy relief", "cough"]),
    ]

    static func category(tags: [String], name: String, source: OpenFactsDatabase) -> ProductCategory {
        let normalizedTags = Set(tags.map(stripLanguage))
        for (category, ruleTags) in tagRules where !normalizedTags.isDisjoint(with: ruleTags) {
            return category
        }
        let lowerName = TextNormalizer.key(name)
        for (category, keywords) in nameRules where keywords.contains(where: { lowerName.contains($0) }) {
            return category
        }
        switch source {
        case .beauty: return .personalCare
        case .food, .products: return .other
        }
    }

    static func stripLanguage(_ tag: String) -> String {
        guard let colon = tag.firstIndex(of: ":") else { return tag }
        return String(tag[tag.index(after: colon)...])
    }
}
