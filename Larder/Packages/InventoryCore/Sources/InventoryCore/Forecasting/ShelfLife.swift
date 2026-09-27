import Foundation

/// Built-in shelf-life defaults, in days, by category and storage climate.
///
/// Values are conservative household guidelines for unopened food, in the
/// spirit of USDA FoodKeeper; they're a starting point that per-product and
/// per-item overrides refine. Household goods have no shelf life (nil).
public enum ShelfLifeTable {
    /// (room, fridge, freezer)
    static let table: [ProductCategory: (Int, Int, Int)] = [
        .produce: (5, 7, 240),
        .meat: (1, 2, 120),
        .seafood: (1, 2, 90),
        .dairy: (1, 7, 90),
        .cheese: (1, 28, 180),
        .eggs: (7, 28, 365),
        .bakery: (5, 10, 90),
        .deli: (1, 5, 60),
        .frozen: (1, 3, 240),
        .grains: (365, 365, 730),
        .canned: (730, 730, 730),
        .condiments: (365, 180, 365),
        .spices: (730, 730, 730),
        .snacks: (90, 90, 180),
        .beverages: (270, 180, 365),
        .leftovers: (1, 4, 90),
    ]

    public static func days(for category: ProductCategory, climate: StorageClimate) -> Int? {
        guard let entry = table[category] else { return nil }
        switch climate {
        case .room: return entry.0
        case .fridge: return entry.1
        case .freezer: return entry.2
        }
    }
}

public struct ExpiryEstimate: Sendable, Equatable {
    public enum Source: String, Sendable {
        /// The product's own shelf life for this climate (user- or Claude-provided).
        case product
        /// The built-in category table.
        case categoryDefault
    }

    public var date: Date
    public var shelfLifeDays: Int
    public var source: Source
}

public enum ExpiryEstimator {
    /// Estimates when an item bought on `purchaseDate` and kept in `climate`
    /// will expire. Returns nil for goods without a shelf life.
    ///
    /// - Parameter productShelfLifeDays: the product's override for this
    ///   climate, which wins over the category table.
    public static func estimate(
        purchaseDate: Date,
        category: ProductCategory,
        climate: StorageClimate,
        productShelfLifeDays: Int? = nil,
        calendar: Calendar = .current
    ) -> ExpiryEstimate? {
        let source: ExpiryEstimate.Source
        let days: Int
        if let productShelfLifeDays, productShelfLifeDays > 0 {
            days = productShelfLifeDays
            source = .product
        } else if let tableDays = ShelfLifeTable.days(for: category, climate: climate) {
            days = tableDays
            source = .categoryDefault
        } else {
            return nil
        }
        guard let date = calendar.date(byAdding: .day, value: days, to: purchaseDate) else { return nil }
        return ExpiryEstimate(date: date, shelfLifeDays: days, source: source)
    }
}
