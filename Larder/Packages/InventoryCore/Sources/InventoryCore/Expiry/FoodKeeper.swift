import Foundation

/// Where and in what state food is kept, as USDA FoodKeeper describes it.
public enum StorageSlot: String, CaseIterable, Sendable {
    case pantry = "p"
    case pantryOpened = "po"
    case fridge = "f"
    case fridgeOpened = "fo"
    case fridgeThawed = "ft"
    case freezer = "z"

    public static func unopened(_ climate: StorageClimate) -> StorageSlot {
        switch climate {
        case .room: .pantry
        case .fridge: .fridge
        case .freezer: .freezer
        }
    }

    public static func opened(_ climate: StorageClimate) -> StorageSlot {
        switch climate {
        case .room: .pantryOpened
        case .fridge: .fridgeOpened
        case .freezer: .freezer
        }
    }
}

/// How long something keeps in one storage slot.
public enum StorageGuidance: Sendable, Hashable {
    /// Keeps for this many days (USDA gives a range).
    case days(ClosedRange<Int>)
    /// Keep until the date on the package.
    case packageDate
    case notRecommended
    case indefinitely
    /// Keep at room temperature until ripe, then refrigerate.
    case whenRipe

    public var range: ClosedRange<Int>? {
        if case .days(let range) = self { return range }
        return nil
    }
}

/// One food in USDA FSIS FoodKeeper ("Salsa, picante and taco sauces").
public struct FoodKeeperEntry: Sendable, Hashable, Identifiable {
    public let id: Int
    public let categoryID: Int
    public let name: String
    public let subtitle: String?
    public let keywords: [String]
    public let guidance: [StorageSlot: StorageGuidance]
    public let tips: [StorageClimate: String]

    /// "Salsa (picante and taco sauces)".
    public var displayName: String {
        guard let subtitle else { return name }
        return "\(name) (\(subtitle))"
    }

    public var categoryName: String { FoodKeeper.categoryNames[categoryID] ?? "" }

    public func unopened(_ climate: StorageClimate) -> StorageGuidance? {
        guidance[StorageSlot.unopened(climate)]
    }

    public func opened(_ climate: StorageClimate) -> StorageGuidance? {
        guidance[StorageSlot.opened(climate)]
    }

    public var thawed: StorageGuidance? { guidance[.fridgeThawed] }

    /// USDA advises against freezing it.
    public var freezingNotRecommended: Bool { guidance[.freezer] == .notRecommended }
}

/// USDA FSIS FoodKeeper storage guidance, bundled with the app (public
/// domain; regenerate with `Larder/scripts/foodkeeper.py`).
public enum FoodKeeper {
    public static var source: String { database.source }
    public static var entries: [FoodKeeperEntry] { database.entries }
    static var categoryNames: [Int: String] { database.categories }

    public static func entry(id: Int) -> FoodKeeperEntry? {
        database.byID[id]
    }

    /// The entry that best fits a product, or nil when nothing fits well.
    public static func match(name: String, brand: String? = nil, category: ProductCategory? = nil) -> FoodKeeperEntry? {
        FoodKeeperMatcher.match(name: name, brand: brand, category: category, index: database.index)
    }

    /// Entries whose name, subtitle or keywords contain every word of
    /// `text`, for picking one by hand.
    public static func search(_ text: String) -> [FoodKeeperEntry] {
        let query = FoodKeeperMatcher.words(text)
        guard !query.isEmpty else { return entries }
        return database.index.filter { indexed in
            let all = indexed.nameWords.union(indexed.subtitleWords).union(indexed.keywordWords)
            return query.allSatisfy { word in all.contains { $0.hasPrefix(word) } }
        }.map(\.entry)
    }

    // MARK: - Loading

    struct Database: Sendable {
        let source: String
        let categories: [Int: String]
        let entries: [FoodKeeperEntry]
        let byID: [Int: FoodKeeperEntry]
        let index: [FoodKeeperMatcher.Indexed]
    }

    static let database: Database = {
        do {
            let raw = try JSONDecoder().decode(RawDatabase.self, from: Data(FoodKeeperData.json.utf8))
            let entries = raw.products.map(\.entry)
            return Database(
                source: raw.source,
                categories: Dictionary(uniqueKeysWithValues: raw.categories.compactMap { key, value in Int(key).map { ($0, value) } }),
                entries: entries,
                byID: Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                index: entries.map(FoodKeeperMatcher.Indexed.init)
            )
        } catch {
            assertionFailure("FoodKeeper data didn't decode: \(error)")
            return Database(source: "", categories: [:], entries: [], byID: [:], index: [])
        }
    }()

    struct RawDatabase: Decodable {
        let source: String
        let categories: [String: String]
        let products: [RawProduct]
    }

    struct RawProduct: Decodable {
        let i: Int
        let c: Int
        let n: String
        let s: String?
        let k: [String]
        let t: [String: RawGuidance]
        let tips: [String: String]?

        var entry: FoodKeeperEntry {
            var guidance: [StorageSlot: StorageGuidance] = [:]
            for (key, value) in t {
                if let slot = StorageSlot(rawValue: key), let parsed = value.guidance { guidance[slot] = parsed }
            }
            var tipsByClimate: [StorageClimate: String] = [:]
            for (key, value) in tips ?? [:] {
                switch key {
                case "p": tipsByClimate[.room] = value
                case "f": tipsByClimate[.fridge] = value
                case "z": tipsByClimate[.freezer] = value
                default: break
                }
            }
            return FoodKeeperEntry(id: i, categoryID: c, name: n, subtitle: s, keywords: k, guidance: guidance, tips: tipsByClimate)
        }
    }

    /// `[min, max]` days or one of "date", "no", "ever", "ripe".
    enum RawGuidance: Decodable {
        case range([Int])
        case code(String)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let range = try? container.decode([Int].self) {
                self = .range(range)
            } else {
                self = .code(try container.decode(String.self))
            }
        }

        var guidance: StorageGuidance? {
            switch self {
            case .range(let values):
                guard let low = values.min(), let high = values.max() else { return nil }
                return .days(max(0, low)...max(0, high))
            case .code("date"): return .packageDate
            case .code("no"): return .notRecommended
            case .code("ever"): return .indefinitely
            case .code("ripe"): return .whenRipe
            case .code: return nil
            }
        }
    }
}

/// Picks the FoodKeeper entry for a grocery name. Scores every entry by the
/// words it shares with the name, then penalizes entries that are a
/// different product ("Lime juice" for limes), a different state
/// ("canned", "fresh", "homemade") or a different kind of food than the
/// product's category. Near-ties go to the lower FoodKeeper ID, which is
/// usually the plain form of a food.
enum FoodKeeperMatcher {
    struct Indexed: Sendable {
        let entry: FoodKeeperEntry
        /// The name split into alternatives ("Ketchup, cocktail, or chili sauce").
        let alternatives: [Set<String>]
        let nameWords: Set<String>
        let subtitleWords: Set<String>
        let keywordWords: Set<String>
        /// The subtitle lists examples ("lemon, lime, orange") rather than
        /// describing a form ("fermented milk").
        let subtitleIsList: Bool

        init(_ entry: FoodKeeperEntry) {
            self.entry = entry
            let separators = [",", "/", " or ", " and "]
            var parts = [entry.name.lowercased()]
            for separator in separators {
                parts = parts.flatMap { $0.components(separatedBy: separator) }
            }
            alternatives = parts.map { Set(FoodKeeperMatcher.words($0)) }.filter { !$0.isEmpty }
            nameWords = Set(FoodKeeperMatcher.words(entry.name))
            subtitleWords = Set(FoodKeeperMatcher.words(entry.subtitle ?? ""))
            keywordWords = Set(entry.keywords.flatMap(FoodKeeperMatcher.words))
            let subtitle = entry.subtitle?.lowercased() ?? ""
            subtitleIsList = subtitle.contains(",") || subtitle.contains("such as") || subtitle.contains("etc")
        }

        var allWords: Set<String> { nameWords.union(subtitleWords).union(keywordWords) }
    }

    static let generic: Set<String> = [
        "and", "or", "in", "of", "the", "with", "a", "an", "to", "for", "as", "such", "etc", "including", "type",
        "style", "plain", "regular", "bottled", "bottle", "package", "packaged", "store", "bought", "commercial",
        "commercially", "product", "goods", "fruit", "vegetable", "part", "other", "all",
    ]
    /// Describe a cut, size or variety rather than the food itself.
    static let weak: Set<String> = [
        "whole", "boneless", "skinless", "bone", "large", "small", "medium", "jumbo", "extra", "organic", "natural",
        "sliced", "diced", "chopped", "minced", "ground", "salted", "unsalted", "sharp", "mild", "lean", "fat",
        "free", "low", "reduced", "baby", "mini",
    ]
    /// In an entry's name, these make it a different product.
    static let nameForms: Set<String> = [
        "juice", "sauce", "salad", "pie", "soup", "oil", "extract", "mix", "chip", "spread", "dip", "paste", "butter",
        "substitute", "imitation", "vegan", "powder", "powdered", "concentrate", "syrup", "vinegar", "bar", "cake",
        "crust", "dough", "seasoning", "stock", "broth", "gravy", "sprout", "seed", "flour", "meal",
    ]
    /// States of preparation.
    static let states: Set<String> = [
        "canned", "frozen", "fresh", "homemade", "cooked", "dried", "dry", "raw", "instant", "shredded", "grated",
        "smoked", "precooked", "uncooked", "squeezed", "fried", "boiled", "evaporated", "condensed", "packet",
        "pickled", "marinated", "prepared", "leftover", "stuffed", "breaded", "thawed", "opened",
    ]
    static let stopWords: Set<String> = [
        "and", "or", "of", "the", "with", "a", "an", "in", "for", "to", "fl", "oz", "lb", "lbs", "g", "kg", "ml", "l",
        "pack", "pk", "ct", "count", "each", "bag", "box", "jar", "bottle",
    ]
    /// Words the product's category implies ("canned" for canned goods).
    static let categoryWords: [ProductCategory: Set<String>] = [
        .grains: ["dry", "dried"],
        .canned: ["canned"],
        .frozen: ["frozen"],
        .leftovers: ["leftover", "cooked"],
        .deli: ["deli", "luncheon"],
    ]
    static let synonyms: [String: [String]] = [
        "spaghetti": ["pasta"], "penne": ["pasta"], "macaroni": ["pasta"], "linguine": ["pasta"],
        "fettuccine": ["pasta"], "rigatoni": ["pasta"], "rotini": ["pasta"], "fusilli": ["pasta"], "orzo": ["pasta"],
        "lasagna": ["pasta"], "noodle": ["pasta"], "marinara": ["spaghetti"], "hamburger": ["beef", "ground"],
        "scallion": ["onion", "green"], "oj": ["orange", "juice"], "pop": ["soda"], "cola": ["soda"],
        "seltzer": ["water"], "sparkling": ["water"], "romaine": ["lettuce"], "iceberg": ["lettuce"],
        "arugula": ["green"], "mesclun": ["green"], "parsley": ["herb"], "dill": ["herb"], "mint": ["herb"],
        "thyme": ["herb"], "rosemary": ["herb"], "bell": ["pepper"], "jalapeno": ["hot", "pepper"],
        "tilapia": ["lean", "fish"], "cod": ["lean", "fish"], "trout": ["fish"], "mandarin": ["tangerine"],
        "feta": ["cheese", "soft"], "steak": ["beef", "steak"], "sirloin": ["beef", "steak"],
        "ribeye": ["beef", "steak"], "yoghurt": ["yogurt"], "donut": ["doughnut"], "chickpea": ["bean"],
        "garbanzo": ["bean"], "catsup": ["ketchup"], "mayo": ["mayonnaise"],
    ]
    /// Which of Larder's categories each FoodKeeper category covers.
    static let categories: [Int: Set<ProductCategory>] = [
        1: [.baby], 2: [.bakery], 3: [.grains, .spices, .condiments], 4: [.bakery, .frozen], 5: [.beverages],
        6: [.condiments, .canned], 7: [.dairy, .cheese, .eggs], 8: [.frozen], 9: [.grains, .canned, .bakery],
        10: [.meat], 11: [.meat, .snacks], 12: [.meat, .deli], 13: [.meat], 14: [.meat, .deli], 15: [.meat],
        16: [.meat, .canned], 17: [.meat], 18: [.produce, .frozen], 19: [.produce, .frozen], 20: [.seafood],
        21: [.seafood], 22: [.seafood], 23: [.canned, .grains, .snacks, .condiments, .spices, .beverages],
        24: [.other, .produce], 25: [.deli, .leftovers],
    ]

    /// A category adds up to 2 points, so a match without one needs less.
    static let minimumScore = 3.0
    static let minimumScoreWithoutCategory = 2.5

    static func match(name: String, brand: String?, category: ProductCategory?, index: [Indexed]) -> FoodKeeperEntry? {
        var query = words(name).filter { !stopWords.contains($0) }
        if let brand {
            let brandWords = Set(words(brand))
            let withoutBrand = query.filter { !brandWords.contains($0) }
            if !withoutBrand.isEmpty { query = withoutBrand }
        }
        guard let head = query.last else { return nil }
        var queryWords = Set(query)
        for word in query {
            for synonym in synonyms[word] ?? [] { queryWords.insert(singular(synonym)) }
        }
        let heads = Set([head] + (synonyms[head] ?? []).map(singular))
        let implied = category.flatMap { categoryWords[$0] } ?? []

        func weight(_ word: String) -> Double {
            weak.contains(word) || states.contains(word) || generic.contains(word) ? 1 : 3
        }

        var scored: [(score: Double, entry: FoodKeeperEntry, hasHead: Bool)] = []
        for indexed in index {
            let inName = queryWords.intersection(indexed.nameWords)
            let inSubtitle = queryWords.intersection(indexed.subtitleWords).subtracting(indexed.nameWords)
            let inKeywords = queryWords.intersection(indexed.keywordWords)
                .subtracting(indexed.nameWords).subtracting(indexed.subtitleWords)
            guard !(inName.isEmpty && inSubtitle.isEmpty && inKeywords.isEmpty) else { continue }

            var score = inName.reduce(0) { $0 + weight($1) }
            score += inSubtitle.reduce(0) { $0 + (indexed.subtitleIsList ? weight($1) : 1) }
            score += Double(inKeywords.count)
            score += Double(implied.intersection(indexed.allWords).subtracting(queryWords).count)

            if !inName.isEmpty {
                let closest = indexed.alternatives.min { $0.subtracting(queryWords).count < $1.subtracting(queryWords).count }
                    ?? indexed.nameWords
                for word in closest.subtracting(queryWords).subtracting(generic).subtracting(implied) {
                    if nameForms.contains(word) {
                        score -= 4
                    } else if !states.contains(word) {
                        score -= 2
                    }
                }
            } else {
                score -= 4 * Double(indexed.nameWords.subtracting(queryWords).subtracting(implied).intersection(nameForms).count)
            }
            let entryStates = indexed.nameWords.union(indexed.subtitleWords).intersection(states)
            if !entryStates.subtracting(queryWords).subtracting(implied).isEmpty {
                score -= 1.5
            }
            score -= 0.05 * Double(indexed.subtitleWords.subtracting(queryWords).subtracting(generic).count)
            if let category {
                let covered = categories[indexed.entry.categoryID] ?? []
                if covered.contains(category) {
                    score += 2
                } else if category != .other {
                    score -= 1
                }
            }
            scored.append((score, indexed.entry, !heads.isDisjoint(with: indexed.allWords)))
        }
        guard !scored.isEmpty else { return nil }
        // When some entries name the head noun ("bread" in "whole wheat
        // bread"), the ones that don't are worse fits.
        if scored.contains(where: \.hasHead) {
            for index in scored.indices where !scored[index].hasHead {
                scored[index].score -= 2
            }
        }
        guard let top = scored.map(\.score).max(), top >= (category == nil ? minimumScoreWithoutCategory : minimumScore) else { return nil }
        return scored
            .filter { $0.score >= top - 0.3 }
            .min { $0.entry.id < $1.entry.id }?
            .entry
    }

    /// Lowercased words with plurals folded; numbers and punctuation dropped.
    static func words(_ text: String) -> [String] {
        let lowered = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
        let cleaned = String(lowered.unicodeScalars.map { scalar -> Character in
            ("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar)) ? Character(scalar) : " "
        })
        return cleaned.split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) }
            .map(singular)
    }

    static func singular(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") { return String(word.dropLast(2)) }
        for suffix in ["ches", "shes", "xes", "sses", "zes"] where word.hasSuffix(suffix) {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is") {
            return String(word.dropLast())
        }
        return word
    }
}
