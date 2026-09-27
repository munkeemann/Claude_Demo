import Foundation

/// How strictly a household reads dates. Picks where in USDA's storage
/// ranges an estimate lands and whether shelf-stable food gets time past
/// its printed "best by" date.
public enum ExpiryStrictness: Int, CaseIterable, Codable, Sendable, Identifiable {
    case veryCautious = 0
    case cautious
    case balanced
    case relaxed
    case veryRelaxed

    public static let `default`: ExpiryStrictness = .balanced

    public var id: Int { rawValue }

    /// 0 (short end of USDA's range) … 1 (long end).
    public var position: Double { Double(rawValue) / Double(Self.allCases.count - 1) }

    /// Share of the category's past-the-date allowance used: none up to
    /// Balanced, all of it at Very relaxed.
    public var graceShare: Double { max(0, (position - 0.5) * 2) }

    public var label: String {
        switch self {
        case .veryCautious: "Very cautious"
        case .cautious: "Cautious"
        case .balanced: "Balanced"
        case .relaxed: "Relaxed"
        case .veryRelaxed: "Very relaxed"
        }
    }

    public var summary: String {
        switch self {
        case .veryCautious: "Uses the shortest time in USDA's range and follows printed dates exactly."
        case .cautious: "Leans toward the short end of USDA's range and follows printed dates exactly."
        case .balanced: "Uses the middle of USDA's range and follows printed dates."
        case .relaxed: "Leans toward the long end of USDA's range, and gives canned and dry goods some time past their best-by date."
        case .veryRelaxed: "Uses the longest time in USDA's range, and gives canned and dry goods the most time past their best-by date."
        }
    }
}

/// Everything that decides when one item should be used or thrown out.
public struct ExpiryInputs: Sendable, Equatable {
    public var category: ProductCategory
    public var foodKeeper: FoodKeeperEntry?
    /// A shelf life for the current climate from elsewhere (Claude, or set
    /// on the product), used when FoodKeeper has nothing.
    public var productShelfLifeDays: Int?
    public var climate: StorageClimate
    public var purchaseDate: Date
    /// When it moved to where it is now; nil means since purchase.
    public var climateSince: Date?
    /// Share (0–1) of its unopened shelf life used up before `climateSince`.
    public var shelfLifeUsed: Double
    public var openedDate: Date?
    /// When it came out of the freezer.
    public var thawedDate: Date?
    /// The date printed on the package.
    public var printedDate: Date?

    public init(
        category: ProductCategory,
        foodKeeper: FoodKeeperEntry? = nil,
        productShelfLifeDays: Int? = nil,
        climate: StorageClimate,
        purchaseDate: Date,
        climateSince: Date? = nil,
        shelfLifeUsed: Double = 0,
        openedDate: Date? = nil,
        thawedDate: Date? = nil,
        printedDate: Date? = nil
    ) {
        self.category = category
        self.foodKeeper = foodKeeper
        self.productShelfLifeDays = productShelfLifeDays
        self.climate = climate
        self.purchaseDate = purchaseDate
        self.climateSince = climateSince
        self.shelfLifeUsed = shelfLifeUsed
        self.openedDate = openedDate
        self.thawedDate = thawedDate
        self.printedDate = printedDate
    }
}

public struct ExpiryResult: Sendable, Equatable {
    public enum Basis: String, Sendable {
        case printedDate
        case foodKeeper
        case productEstimate
        case categoryDefault
        /// It keeps indefinitely, or nothing is known.
        case none
    }

    /// When to use it by; nil when it keeps indefinitely or nothing is known.
    public var date: Date?
    public var basis: Basis
    /// What decided the date, for the item screen.
    public var explanation: String?
}

/// Works out an item's use-by date from USDA FoodKeeper guidance, the date
/// on the package and the household's strictness.
///
/// - Unopened food: FoodKeeper's range for where it's kept, counted from
///   purchase. Strictness picks the point in the range. Moving between the
///   pantry and fridge carries over the share of shelf life already used.
/// - A printed date replaces the unopened estimate. Relaxed households give
///   shelf-stable categories time past it; guarded categories never get any.
/// - Opened food: FoodKeeper's after-opening time from the day it was
///   opened, when that comes sooner.
/// - Frozen food: the freezer time from the day it went in. Thawed food:
///   the after-thawing time from the day it came out.
///
/// Meat, poultry, seafood, deli, dairy, cheese, leftovers and baby food
/// never go past the long end of USDA's range, whatever the strictness.
public enum ExpiryCalculator {
    public static let guardedCategories: Set<ProductCategory> = [.meat, .seafood, .deli, .dairy, .cheese, .leftovers, .baby]

    /// Days past a printed date allowed at Very relaxed, by category.
    static let printedDateAllowance: [ProductCategory: Int] = [
        .canned: 365, .spices: 365, .grains: 180, .condiments: 90, .beverages: 60, .frozen: 90,
        .snacks: 30, .eggs: 14, .bakery: 2, .produce: 1,
    ]

    /// After-opening days when FoodKeeper has none: (pantry, fridge).
    static let openedFallback: [ProductCategory: (Int?, Int)] = [
        .dairy: (nil, 7), .cheese: (nil, 21), .deli: (nil, 5), .meat: (nil, 3), .seafood: (nil, 2),
        .condiments: (60, 60), .canned: (nil, 4), .beverages: (3, 7), .snacks: (14, 30), .bakery: (5, 7),
        .grains: (180, 180), .leftovers: (nil, 3), .baby: (nil, 2),
    ]

    public static func isGuarded(_ category: ProductCategory) -> Bool {
        guardedCategories.contains(category)
    }

    public static func compute(
        _ inputs: ExpiryInputs,
        strictness: ExpiryStrictness,
        calendar: Calendar = .current
    ) -> ExpiryResult {
        let entry = inputs.foodKeeper

        // Frozen: the freezer clock starts when it went in.
        if inputs.climate == .freezer {
            let start = inputs.climateSince ?? inputs.purchaseDate
            let frozen = unopenedDays(inputs, climate: .freezer, strictness: strictness)
            guard let days = frozen.value else { return ExpiryResult(date: nil, basis: frozen.basis, explanation: frozen.explanation) }
            return ExpiryResult(date: add(days, to: start, calendar), basis: frozen.basis, explanation: frozen.explanation)
        }

        // Thawed: counted from the day it came out.
        if let thawed = inputs.thawedDate {
            if let range = entry?.thawed?.range ?? entry?.opened(.fridge)?.range {
                let days = pick(range, strictness)
                return ExpiryResult(date: add(days, to: thawed, calendar), basis: .foodKeeper, explanation: "USDA: \(describe(range)) in the fridge after thawing")
            }
            // No thawing guidance: a few days at most, from thawing.
            let days = unopenedDays(inputs, climate: inputs.climate, strictness: strictness)
            let fallback = min(days.value ?? 3, 3)
            return ExpiryResult(date: add(fallback, to: thawed, calendar), basis: days.basis, explanation: "About \(describe(fallback...fallback)) after thawing")
        }

        // Unopened: printed date or estimate.
        var unopened: ExpiryResult
        if let printed = inputs.printedDate {
            let grace = printedDateGrace(category: inputs.category, strictness: strictness)
            let explanation = grace > 0
                ? "Package date plus \(grace == 1 ? "1 day" : "\(grace) days") (\(strictness.label.lowercased()))"
                : "Date on the package"
            unopened = ExpiryResult(date: add(grace, to: printed, calendar), basis: .printedDate, explanation: explanation)
        } else {
            let days = unopenedDays(inputs, climate: inputs.climate, strictness: strictness)
            if let value = days.value {
                let start = inputs.climateSince ?? inputs.purchaseDate
                let remaining = Int((Double(value) * (1 - min(max(inputs.shelfLifeUsed, 0), 1))).rounded())
                unopened = ExpiryResult(date: add(remaining, to: start, calendar), basis: days.basis, explanation: days.explanation)
            } else {
                unopened = ExpiryResult(date: nil, basis: days.basis, explanation: days.explanation)
            }
        }

        // Opened: after-opening time, when sooner.
        guard let opened = inputs.openedDate else { return unopened }
        let openedResult: ExpiryResult?
        switch entry?.opened(inputs.climate) {
        case .days(let range):
            let days = pick(range, strictness)
            openedResult = ExpiryResult(
                date: add(days, to: opened, calendar),
                basis: .foodKeeper,
                explanation: "USDA: \(describe(range)) \(inputs.climate == .room ? "in the pantry" : "in the fridge") once opened"
            )
        case .notRecommended:
            openedResult = ExpiryResult(
                date: add(1, to: opened, calendar),
                basis: .foodKeeper,
                explanation: "USDA doesn't recommend keeping it here once opened"
            )
        case .packageDate, .indefinitely:
            openedResult = nil
        case .whenRipe, nil:
            if let fallback = openedFallback[inputs.category] {
                let days = inputs.climate == .room ? fallback.0 : fallback.1
                openedResult = days.map { days in
                    ExpiryResult(date: add(days, to: opened, calendar), basis: .categoryDefault, explanation: "About \(describe(days...days)) once opened")
                }
            } else {
                openedResult = nil
            }
        }
        guard let openedResult, let openedDate = openedResult.date else { return unopened }
        guard let unopenedDate = unopened.date else { return openedResult }
        return openedDate < unopenedDate ? openedResult : unopened
    }

    /// Days past a printed date the household's strictness allows.
    public static func printedDateGrace(category: ProductCategory, strictness: ExpiryStrictness) -> Int {
        guard !isGuarded(category), let allowance = printedDateAllowance[category] else { return 0 }
        return Int((Double(allowance) * strictness.graceShare).rounded())
    }

    /// Unopened shelf life in a climate. `value` is nil when it keeps
    /// indefinitely or nothing is known.
    public static func unopenedDays(
        _ inputs: ExpiryInputs,
        climate: StorageClimate,
        strictness: ExpiryStrictness
    ) -> (value: Int?, basis: ExpiryResult.Basis, explanation: String?) {
        let place = climate == .room ? "in the pantry" : (climate == .fridge ? "in the fridge" : "in the freezer")
        switch inputs.foodKeeper?.unopened(climate) {
        case .days(let range):
            return (pick(range, strictness), .foodKeeper, "USDA: \(describe(range)) \(place)")
        case .indefinitely:
            return (nil, .none, "USDA: keeps indefinitely \(place)")
        case .packageDate, .whenRipe, .notRecommended, nil:
            break
        }
        let guarded = isGuarded(inputs.category)
        if let days = inputs.productShelfLifeDays, days > 0 {
            return (pick(synthesizedRange(days, guarded: guarded), strictness), .productEstimate, "About \(describe(days...days)) \(place)")
        }
        if let days = ShelfLifeTable.days(for: inputs.category, climate: climate) {
            return (pick(synthesizedRange(days, guarded: guarded), strictness), .categoryDefault, "Typical for \(inputs.category.displayName.lowercased()) \(place)")
        }
        return (nil, .none, nil)
    }

    /// The share of unopened shelf life used by `date`, for carrying over
    /// when something moves between the pantry and the fridge.
    public static func shelfLifeUsed(_ inputs: ExpiryInputs, at date: Date, strictness: ExpiryStrictness) -> Double {
        guard inputs.climate != .freezer, inputs.thawedDate == nil,
              let days = unopenedDays(inputs, climate: inputs.climate, strictness: strictness).value, days > 0
        else { return inputs.shelfLifeUsed }
        let start = inputs.climateSince ?? inputs.purchaseDate
        let elapsed = max(0, date.timeIntervalSince(start)) / 86_400
        return min(1, max(0, inputs.shelfLifeUsed) + elapsed / Double(days))
    }

    /// A single estimate as a range: guarded food never goes past it.
    static func synthesizedRange(_ days: Int, guarded: Bool) -> ClosedRange<Int> {
        let spread = Int((Double(days) / 4).rounded())
        return max(0, days - spread)...(guarded ? days : days + spread)
    }

    static func pick(_ range: ClosedRange<Int>, _ strictness: ExpiryStrictness) -> Int {
        range.lowerBound + Int((Double(range.upperBound - range.lowerBound) * strictness.position).rounded())
    }

    static func add(_ days: Int, to date: Date, _ calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: days, to: date)
    }

    /// "3–5 days", "1–2 weeks", "12–18 months", "2 years".
    public static func describe(_ range: ClosedRange<Int>) -> String {
        let (low, high) = (range.lowerBound, range.upperBound)
        func format(_ divisor: Int, _ unit: String) -> String {
            let a = Int((Double(low) / Double(divisor)).rounded())
            let b = Int((Double(high) / Double(divisor)).rounded())
            return a == b ? "\(a) \(a == 1 ? unit : unit + "s")" : "\(a)–\(b) \(unit)s"
        }
        if high >= 730 && (low % 365 == 0 || low >= 365) { return format(365, "year") }
        if high >= 60 && (low % 30 == 0 || low >= 30) || (low == high && low >= 30 && low % 30 == 0) {
            return format(30, "month")
        }
        if high >= 14, low % 7 == 0, high % 7 == 0 { return format(7, "week") }
        return format(1, "day")
    }
}
