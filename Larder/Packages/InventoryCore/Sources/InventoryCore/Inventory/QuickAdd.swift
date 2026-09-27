import Foundation

/// One item from a typed or dictated list ("2 lb chicken thighs").
public struct QuickAddItem: Codable, Sendable, Hashable {
    public var name: String
    public var brand: String?
    public var category: ProductCategory
    public var quantity: Double
    public var unit: MeasureUnit
    public var packageSize: String?
    /// Where it's normally kept once home.
    public var storage: StorageClimate?
    public var shelfLifeDays: Int?

    public init(
        name: String,
        brand: String? = nil,
        category: ProductCategory,
        quantity: Double = 1,
        unit: MeasureUnit? = nil,
        packageSize: String? = nil,
        storage: StorageClimate? = nil,
        shelfLifeDays: Int? = nil
    ) {
        self.name = name
        self.brand = brand
        self.category = category
        self.quantity = quantity
        self.unit = unit ?? category.defaultUnit
        self.packageSize = packageSize
        self.storage = storage
        self.shelfLifeDays = shelfLifeDays
    }

    enum CodingKeys: String, CodingKey {
        case name, brand, category, quantity, unit, packageSize, storage, shelfLifeDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand).flatMap { $0.isEmpty ? nil : $0 }
        category = (try? container.decode(ProductCategory.self, forKey: .category)) ?? .other
        quantity = (try? container.decode(Double.self, forKey: .quantity)).flatMap { $0 > 0 ? $0 : nil } ?? 1
        unit = (try? container.decode(MeasureUnit.self, forKey: .unit)) ?? category.defaultUnit
        packageSize = try container.decodeIfPresent(String.self, forKey: .packageSize).flatMap { $0.isEmpty ? nil : $0 }
        storage = try? container.decodeIfPresent(StorageClimate.self, forKey: .storage)
        let days = (try? container.decodeIfPresent(Int.self, forKey: .shelfLifeDays))
            ?? (try? container.decodeIfPresent(Double.self, forKey: .shelfLifeDays)).map { Int($0.rounded()) }
        shelfLifeDays = days.flatMap { $0 > 0 ? $0 : nil }
    }

    /// A review line; `locationID` is where its storage climate lives.
    public func line(locationID: UUID?) -> ShelfScanLine {
        ShelfScanLine(
            name: name,
            brand: brand ?? "",
            category: category,
            quantity: quantity,
            unit: unit,
            packageSize: packageSize,
            shelfLifeDays: shelfLifeDays,
            locationID: locationID
        )
    }
}

public struct QuickAddResult: Codable, Sendable, Equatable {
    public var items: [QuickAddItem]

    public init(items: [QuickAddItem]) {
        self.items = items
    }
}

public enum QuickAddSchema {
    public static let schema: JSONValue = JSONSchema.object([
        ("items", JSONSchema.array(of: JSONSchema.object([
            ("name", JSONSchema.string("Everyday product name, capitalized, without brand or amount: 'Chicken Thighs'.")),
            ("brand", JSONSchema.nullable(JSONSchema.string())),
            ("category", JSONSchema.enumeration(ProductCategory.allCases.map(\.rawValue))),
            ("quantity", JSONSchema.number()),
            ("unit", JSONSchema.enumeration(MeasureUnit.allCases.map(\.rawValue))),
            ("packageSize", JSONSchema.nullable(JSONSchema.string("Size of one package when said, e.g. '5 lb'."))),
            ("storage", JSONSchema.nullable(JSONSchema.enumeration(StorageClimate.allCases.map(\.rawValue), description: "Where it's normally kept at home: room (pantry), fridge or freezer."))),
            ("shelfLifeDays", JSONSchema.nullable(JSONSchema.integer("Typical days until spoiled where it's kept, for perishables."))),
        ]))),
    ])
}

public enum QuickAddPrompt {
    public static let system = """
    You turn a household's typed or dictated list of things they just got into inventory items. The \
    text may be one per line, comma-separated or run-on speech ("milk eggs two pounds of chicken and \
    some bananas"), with dictation mistakes.

    Rules:
    - One entry per distinct thing. Keep amounts that were said ("two pounds" is quantity 2, unit "lb"; \
    "a dozen eggs" is quantity 1, unit "dozen"; "3 cans of beans" is quantity 3, unit "can").
    - Without an amount: quantity 1 with a sensible unit (a loaf of bread is 1 "each", milk is 1 "gal" \
    in the US, a bag of potatoes is 1 "bag").
    - brand: keep any brand that was said or typed ("tillamook cheddar" is brand "Tillamook", name \
    "Cheddar Cheese"; "kirkland paper towels" is brand "Kirkland Signature"). Brands this household \
    already buys are listed; use their spelling. Null when no brand was mentioned.
    - Fix obvious dictation errors and capitalize names. Don't invent items that weren't mentioned.
    - storage: where it's normally kept (potatoes, onions and bananas in the pantry; frozen foods in \
    the freezer).
    """

    public static func userText(for text: String, knownBrands: [String] = []) -> String {
        var sections: [String] = []
        if !knownBrands.isEmpty {
            sections.append("Brands this household buys: \(knownBrands.joined(separator: ", ")).")
        }
        sections.append("The list:\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        return sections.joined(separator: "\n\n")
    }
}

/// Parses a list on the phone, for when there's no Claude key (and for
/// Siri). Handles one item per line or comma, leading amounts ("2 lb",
/// "a dozen", "three cans of") and guesses the category.
public enum QuickAddParser {
    /// Foods whose names contain "and"; everything else splits on it.
    static let joinedNames = [
        "half and half", "mac and cheese", "macaroni and cheese", "salt and pepper", "sour cream and onion",
        "peanut butter and jelly", "rice and beans", "pork and beans", "fish and chips", "franks and beans",
    ]

    static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "half": 0.5, "couple": 2, "few": 3, "some": 1,
    ]

    static let unitWords: [String: MeasureUnit] = [
        "lb": .pound, "lbs": .pound, "pound": .pound, "pounds": .pound, "oz": .ounce, "ounce": .ounce, "ounces": .ounce,
        "g": .gram, "gram": .gram, "grams": .gram, "kg": .kilogram, "kilo": .kilogram, "kilos": .kilogram,
        "gal": .gallon, "gallon": .gallon, "gallons": .gallon, "qt": .quart, "quart": .quart, "quarts": .quart,
        "pint": .pint, "pints": .pint, "liter": .liter, "liters": .liter, "litre": .liter, "litres": .liter,
        "ml": .milliliter, "dozen": .dozen, "can": .can, "cans": .can, "jar": .jar, "jars": .jar, "box": .box,
        "boxes": .box, "bag": .bag, "bags": .bag, "bottle": .bottle, "bottles": .bottle, "pack": .pack,
        "packs": .pack, "package": .pack, "packages": .pack, "roll": .roll, "rolls": .roll, "carton": .each,
        "cartons": .each, "loaf": .each, "loaves": .each, "bunch": .each, "bunches": .each, "head": .each,
        "heads": .each,
    ]

    /// - Parameter knownBrands: brands the household buys; a piece starting
    ///   with one ("tillamook cheddar") keeps it as the brand.
    public static func parse(_ text: String, knownBrands: [String] = []) -> [QuickAddItem] {
        // Longest first, so "Trader Joe's" wins over "Trader".
        let brands = knownBrands
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        return pieces(of: text).compactMap { item(from: $0, knownBrands: brands) }
    }

    /// The list split into one string per item.
    static func pieces(of text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n•")
        return text.components(separatedBy: separators).flatMap { piece -> [String] in
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = trimmed.lowercased()
            guard lowered.contains(" and "), !joinedNames.contains(where: { lowered.contains($0) }) else { return [trimmed] }
            return trimmed.components(separatedBy: " and ").flatMap { $0.components(separatedBy: " And ") }
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-"))) }
        .map { $0.hasPrefix("and ") ? String($0.dropFirst(4)) : $0 }
        .filter { !$0.isEmpty }
    }

    static func item(from piece: String, knownBrands: [String] = []) -> QuickAddItem? {
        var words = piece.split(separator: " ").map(String.init)
        var quantity: Double?
        var unit: MeasureUnit?

        // "2", "1.5", "1/2", "a", "two", "half a"
        if let first = words.first {
            let lowered = first.lowercased()
            if let value = Double(lowered) {
                quantity = value
                words.removeFirst()
            } else if lowered.contains("/"), let fraction = fraction(lowered) {
                quantity = fraction
                words.removeFirst()
            } else if let value = numberWords[lowered], lowered != "half" || isHalfAmount(words) {
                quantity = value
                words.removeFirst()
                if lowered == "half", ["a", "an"].contains(words.first?.lowercased() ?? "") { words.removeFirst() }
            }
        }
        // "2lb" written together
        if quantity == nil, let first = words.first, let split = splitNumberAndUnit(first) {
            quantity = split.0
            unit = split.1
            words.removeFirst()
        }
        if unit == nil, let first = words.first?.lowercased(), let found = unitWords[first] {
            unit = found
            words.removeFirst()
            if found == .dozen, quantity == nil { quantity = 1 }
        }
        if words.first?.lowercased() == "of" { words.removeFirst() }

        var name = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        var brand: String?
        for known in knownBrands {
            let prefix = known.lowercased() + " "
            if name.lowercased().hasPrefix(prefix), name.count > prefix.count {
                brand = known
                name = String(name.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        guard !name.isEmpty else { return nil }
        let entry = FoodKeeper.match(name: name)
        let category = ProductCategoryGuess.category(for: name, foodKeeper: entry)
        var resolvedUnit = unit ?? category.defaultUnit
        var resolvedQuantity = quantity ?? 1
        // "a dozen eggs" against eggs counted by the dozen; "12 eggs" is 1 dozen.
        if category == .eggs, unit == nil, let count = quantity, count >= 6 {
            resolvedQuantity = count / 12
            resolvedUnit = .dozen
        }
        if unit == nil, quantity != nil, category.defaultUnit != .each, category != .eggs {
            // "3 bananas": a count, not 3 of the category's usual unit.
            resolvedUnit = .each
        }
        return QuickAddItem(
            name: capitalized(name),
            brand: brand,
            category: category,
            quantity: resolvedQuantity,
            unit: resolvedUnit,
            storage: ProductCategoryGuess.storage(for: category, foodKeeper: entry)
        )
    }

    /// "half a gallon", "half gallon": an amount. "half and half": a food.
    static func isHalfAmount(_ words: [String]) -> Bool {
        guard words.count > 1 else { return false }
        let next = words[1].lowercased()
        return next == "a" || next == "an" || unitWords[next] != nil
    }

    static func fraction(_ text: String) -> Double? {
        let parts = text.split(separator: "/")
        guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 else { return nil }
        return a / b
    }

    static func splitNumberAndUnit(_ word: String) -> (Double, MeasureUnit)? {
        let lowered = word.lowercased()
        guard let index = lowered.firstIndex(where: { $0.isLetter }), index != lowered.startIndex,
              let value = Double(lowered[..<index]), let unit = unitWords[String(lowered[index...])]
        else { return nil }
        return (value, unit)
    }

    static func capitalized(_ name: String) -> String {
        name.split(separator: " ").map { word in
            word.count <= 2 && word.allSatisfy(\.isUppercase) ? String(word) : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}

/// Best guesses of a product's category and storage from its name.
public enum ProductCategoryGuess {
    static let household: [(words: [String], category: ProductCategory)] = [
        (["paper towel", "toilet paper", "tissue", "napkin", "paper plate", "foil", "plastic wrap", "zip bag", "ziploc", "trash bag", "garbage bag"], .paperGoods),
        (["detergent", "fabric softener", "dryer sheet", "stain remover"], .laundry),
        (["dish soap", "dishwasher", "bleach", "cleaner", "sponge", "disinfect", "wipes"], .cleaning),
        (["shampoo", "conditioner", "toothpaste", "toothbrush", "deodorant", "razor", "lotion", "body wash", "floss", "soap"], .personalCare),
        (["diaper", "formula", "baby food"], .baby),
        (["dog food", "cat food", "litter", "treats for", "pet food"], .pet),
        (["vitamin", "ibuprofen", "acetaminophen", "bandage", "allergy", "medicine"], .health),
    ]

    public static func category(for name: String, foodKeeper entry: FoodKeeperEntry?) -> ProductCategory {
        let lowered = name.lowercased()
        for group in household where group.words.contains(where: { lowered.contains($0) }) {
            return group.category
        }
        if lowered.hasPrefix("frozen ") || lowered.contains(" frozen ") { return .frozen }
        guard let entry else { return .other }
        let entryName = (entry.name + " " + (entry.subtitle ?? "")).lowercased()
        switch entry.categoryID {
        case 1: return .baby
        case 2, 4: return .bakery
        case 3: return entryName.contains("spice") || entryName.contains("herb") ? .spices : .grains
        case 5: return .beverages
        case 6: return entryName.contains("canned") ? .canned : .condiments
        case 7:
            if entryName.contains("cheese") { return .cheese }
            if entryName.hasPrefix("egg") { return .eggs }
            return .dairy
        case 8: return .frozen
        case 9: return .grains
        case 10, 11, 12, 13, 15, 16, 17: return .meat
        case 14: return .meat
        case 18, 19: return .produce
        case 20, 21, 22: return .seafood
        case 23:
            let snacks = ["chip", "cracker", "pretzel", "popcorn", "cookie", "nut", "granola", "bar", "jerky"]
            if snacks.contains(where: { entryName.contains($0) }) { return .snacks }
            if entryName.contains("cereal") || entryName.contains("rice") || entryName.contains("pasta") { return .grains }
            if entryName.contains("oil") || entryName.contains("peanut butter") || entryName.contains("syrup") { return .condiments }
            if entryName.contains("pepper") || entryName.contains("powder") || entryName.contains("spice") { return .spices }
            return .canned
        case 24: return .other
        case 25: return .deli
        default: return .other
        }
    }

    /// Where it's kept: USDA's pantry-or-fridge advice for produce, else the
    /// category's usual place.
    public static func storage(for category: ProductCategory, foodKeeper entry: FoodKeeperEntry?) -> StorageClimate {
        if let entry, category == .produce || category == .other {
            let pantry = entry.unopened(.room)
            let fridge = entry.unopened(.fridge)
            if case .days = pantry, fridge == nil || pantry?.range?.upperBound ?? 0 >= fridge?.range?.upperBound ?? 0 {
                return .room
            }
            if pantry == .whenRipe { return .room }
            if fridge != nil { return .fridge }
        }
        return category.defaultClimate
    }
}
