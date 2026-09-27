import Foundation

/// A product with purchase and usage history, expressed in days relative to
/// "today" so the data stays fresh whenever it is loaded.
public struct SampleProduct: Sendable {
    public var name: String
    public var brand: String?
    public var category: ProductCategory
    public var unit: MeasureUnit
    public var location: LocationKind
    public var barcode: String?
    public var packageSizeText: String?
    /// The item currently in stock, if any.
    public var stock: SampleStock?
    public var purchases: [SamplePurchase]
    public var usages: [SampleUsage]
}

public struct SampleStock: Sendable {
    public var quantity: Double
    public var initialQuantity: Double
    public var purchasedDaysAgo: Int
    /// Days from today until expiry. Negative means already expired.
    public var expiresInDays: Int?
}

public struct SamplePurchase: Sendable {
    public var daysAgo: Int
    public var quantity: Double
    public var priceCents: Int?
    public var store: String?
}

public struct SampleUsage: Sendable {
    public var daysAgo: Int
    public var quantity: Double
    public var type: UsageType
}

/// Demo inventory used by the Debug "Load sample data" action, previews and tests.
///
/// The histories are shaped to exercise forecasting: milk and coffee are
/// bought on a steady cadence with "used up" taps, toilet paper monthly,
/// spinach is about to expire, dish soap is low, and a few pantry staples have
/// a single purchase (thin history → category defaults).
public enum SampleData {
    public static let products: [SampleProduct] = [
        // MARK: Fridge
        SampleProduct(
            name: "Whole Milk", brand: "Great Value", category: .dairy, unit: .gallon, location: .fridge,
            barcode: "0078742371937", packageSizeText: "1 gal",
            stock: SampleStock(quantity: 0.6, initialQuantity: 1, purchasedDaysAgo: 3, expiresInDays: 6),
            purchases: steady(every: 7, count: 7, lastDaysAgo: 3, quantity: 1, priceCents: 342, store: "Walmart"),
            usages: [10, 17, 24, 31, 38, 45].map { SampleUsage(daysAgo: $0 - 6, quantity: 1, type: .usedUp) }
        ),
        SampleProduct(
            name: "Large Eggs", brand: "Great Value", category: .eggs, unit: .dozen, location: .fridge,
            packageSizeText: "12 ct",
            stock: SampleStock(quantity: 0.5, initialQuantity: 1, purchasedDaysAgo: 5, expiresInDays: 23),
            purchases: steady(every: 14, count: 4, lastDaysAgo: 5, quantity: 1, priceCents: 289, store: "Walmart"),
            usages: [SampleUsage(daysAgo: 7, quantity: 1, type: .usedUp), SampleUsage(daysAgo: 21, quantity: 1, type: .usedUp)]
        ),
        SampleProduct(
            name: "Baby Spinach", brand: "Marketside", category: .produce, unit: .each, location: .fridge,
            packageSizeText: "5 oz",
            stock: SampleStock(quantity: 1, initialQuantity: 1, purchasedDaysAgo: 6, expiresInDays: 1),
            purchases: [SamplePurchase(daysAgo: 6, quantity: 1, priceCents: 248, store: "Walmart"),
                        SamplePurchase(daysAgo: 20, quantity: 1, priceCents: 248, store: "Walmart")],
            usages: [SampleUsage(daysAgo: 14, quantity: 1, type: .discarded)]
        ),
        SampleProduct(
            name: "Boneless Skinless Chicken Breast", brand: nil, category: .meat, unit: .pound, location: .fridge,
            stock: SampleStock(quantity: 2.1, initialQuantity: 2.1, purchasedDaysAgo: 1, expiresInDays: 1),
            purchases: [SamplePurchase(daysAgo: 1, quantity: 2.1, priceCents: 1029, store: "Walmart"),
                        SamplePurchase(daysAgo: 12, quantity: 1.8, priceCents: 882, store: "Walmart")],
            usages: [SampleUsage(daysAgo: 10, quantity: 1.8, type: .usedUp)]
        ),
        SampleProduct(
            name: "Sharp Cheddar Cheese", brand: "Tillamook", category: .cheese, unit: .ounce, location: .fridge,
            stock: SampleStock(quantity: 5, initialQuantity: 8, purchasedDaysAgo: 9, expiresInDays: 21),
            purchases: [SamplePurchase(daysAgo: 9, quantity: 8, priceCents: 449, store: "Walmart")],
            usages: [SampleUsage(daysAgo: 4, quantity: 3, type: .partiallyUsed)]
        ),
        SampleProduct(
            name: "Plain Greek Yogurt", brand: "Fage", category: .dairy, unit: .ounce, location: .fridge,
            packageSizeText: "32 oz",
            stock: SampleStock(quantity: 12, initialQuantity: 32, purchasedDaysAgo: 9, expiresInDays: 5),
            purchases: [SamplePurchase(daysAgo: 9, quantity: 32, priceCents: 697, store: "Target")],
            usages: []
        ),
        SampleProduct(
            name: "Roma Tomatoes", brand: nil, category: .produce, unit: .each, location: .fridge,
            stock: SampleStock(quantity: 4, initialQuantity: 6, purchasedDaysAgo: 4, expiresInDays: 3),
            purchases: [SamplePurchase(daysAgo: 4, quantity: 6, priceCents: 180, store: "Walmart")],
            usages: [SampleUsage(daysAgo: 2, quantity: 2, type: .partiallyUsed)]
        ),

        // MARK: Freezer
        SampleProduct(
            name: "Ground Beef 80/20", brand: nil, category: .meat, unit: .pound, location: .freezer,
            stock: SampleStock(quantity: 1, initialQuantity: 1, purchasedDaysAgo: 20, expiresInDays: 100),
            purchases: [SamplePurchase(daysAgo: 20, quantity: 1, priceCents: 548, store: "Walmart")],
            usages: []
        ),
        SampleProduct(
            name: "Frozen Sweet Peas", brand: "Birds Eye", category: .frozen, unit: .bag, location: .freezer,
            packageSizeText: "12 oz",
            stock: SampleStock(quantity: 1, initialQuantity: 1, purchasedDaysAgo: 30, expiresInDays: 240),
            purchases: [SamplePurchase(daysAgo: 30, quantity: 1, priceCents: 199, store: "Target")],
            usages: []
        ),

        // MARK: Pantry
        SampleProduct(
            name: "Bananas", brand: nil, category: .produce, unit: .pound, location: .pantry,
            stock: SampleStock(quantity: 2.3, initialQuantity: 2.3, purchasedDaysAgo: 2, expiresInDays: 4),
            purchases: steady(every: 7, count: 4, lastDaysAgo: 2, quantity: 2.3, priceCents: 133, store: "Walmart"),
            usages: []
        ),
        SampleProduct(
            name: "Sourdough Bread", brand: "Bakery", category: .bakery, unit: .each, location: .pantry,
            stock: SampleStock(quantity: 1, initialQuantity: 1, purchasedDaysAgo: 4, expiresInDays: 2),
            purchases: [SamplePurchase(daysAgo: 4, quantity: 1, priceCents: 399, store: "Target")],
            usages: []
        ),
        SampleProduct(
            name: "Yellow Onions", brand: nil, category: .produce, unit: .each, location: .pantry,
            packageSizeText: "3 lb",
            stock: SampleStock(quantity: 5, initialQuantity: 6, purchasedDaysAgo: 8, expiresInDays: 22),
            purchases: [SamplePurchase(daysAgo: 8, quantity: 6, priceCents: 297, store: "Walmart")],
            usages: []
        ),
        SampleProduct(
            name: "Garlic", brand: nil, category: .produce, unit: .each, location: .pantry,
            stock: SampleStock(quantity: 2, initialQuantity: 3, purchasedDaysAgo: 8, expiresInDays: 60),
            purchases: [SamplePurchase(daysAgo: 8, quantity: 3, priceCents: 150, store: "Walmart")],
            usages: []
        ),
        SampleProduct(
            name: "Spaghetti", brand: "Barilla", category: .grains, unit: .box, location: .pantry,
            barcode: "0076808280593", packageSizeText: "16 oz",
            stock: SampleStock(quantity: 2, initialQuantity: 2, purchasedDaysAgo: 15, expiresInDays: nil),
            purchases: [SamplePurchase(daysAgo: 15, quantity: 2, priceCents: 358, store: "Walmart")],
            usages: []
        ),
        SampleProduct(
            name: "Jasmine Rice", brand: "Mahatma", category: .grains, unit: .bag, location: .pantry,
            packageSizeText: "5 lb",
            stock: SampleStock(quantity: 1, initialQuantity: 1, purchasedDaysAgo: 40, expiresInDays: nil),
            purchases: [SamplePurchase(daysAgo: 40, quantity: 1, priceCents: 699, store: "Walmart")],
            usages: []
        ),
        SampleProduct(
            name: "Black Beans", brand: "Bush's", category: .canned, unit: .can, location: .pantry,
            packageSizeText: "15 oz",
            stock: SampleStock(quantity: 3, initialQuantity: 4, purchasedDaysAgo: 25, expiresInDays: nil),
            purchases: [SamplePurchase(daysAgo: 25, quantity: 4, priceCents: 396, store: "Walmart")],
            usages: [SampleUsage(daysAgo: 12, quantity: 1, type: .partiallyUsed)]
        ),
        SampleProduct(
            name: "Marinara Sauce", brand: "Rao's", category: .condiments, unit: .jar, location: .pantry,
            packageSizeText: "24 oz",
            stock: SampleStock(quantity: 1, initialQuantity: 1, purchasedDaysAgo: 15, expiresInDays: nil),
            purchases: [SamplePurchase(daysAgo: 15, quantity: 1, priceCents: 799, store: "Target")],
            usages: []
        ),
        SampleProduct(
            name: "Extra Virgin Olive Oil", brand: "California Olive Ranch", category: .condiments, unit: .bottle,
            location: .pantry, packageSizeText: "16.9 fl oz",
            stock: SampleStock(quantity: 0.4, initialQuantity: 1, purchasedDaysAgo: 35, expiresInDays: nil),
            purchases: [SamplePurchase(daysAgo: 35, quantity: 1, priceCents: 1099, store: "Target")],
            usages: []
        ),
        SampleProduct(
            name: "Whole Bean Coffee", brand: "Peet's", category: .beverages, unit: .bag, location: .pantry,
            packageSizeText: "12 oz",
            stock: SampleStock(quantity: 0.7, initialQuantity: 1, purchasedDaysAgo: 4, expiresInDays: nil),
            purchases: steady(every: 12, count: 6, lastDaysAgo: 4, quantity: 1, priceCents: 1099, store: "Target"),
            usages: [16, 28, 40, 52, 64].map { SampleUsage(daysAgo: $0 - 11, quantity: 1, type: .usedUp) }
        ),

        // MARK: Household
        SampleProduct(
            name: "Toilet Paper Mega Rolls", brand: "Charmin", category: .paperGoods, unit: .pack, location: .bathroom,
            packageSizeText: "12 rolls",
            stock: SampleStock(quantity: 0.5, initialQuantity: 1, purchasedDaysAgo: 8, expiresInDays: nil),
            purchases: [38, 67, 98, 8].map { SamplePurchase(daysAgo: $0, quantity: 1, priceCents: 1597, store: "Target") },
            usages: [SampleUsage(daysAgo: 9, quantity: 1, type: .usedUp), SampleUsage(daysAgo: 39, quantity: 1, type: .usedUp)]
        ),
        SampleProduct(
            name: "Paper Towels", brand: "Bounty", category: .paperGoods, unit: .pack, location: .cleaning,
            packageSizeText: "6 rolls",
            stock: SampleStock(quantity: 1, initialQuantity: 1, purchasedDaysAgo: 15, expiresInDays: nil),
            purchases: [100, 58, 15].map { SamplePurchase(daysAgo: $0, quantity: 1, priceCents: 1349, store: "Target") },
            usages: []
        ),
        SampleProduct(
            name: "Dish Soap", brand: "Dawn", category: .cleaning, unit: .bottle, location: .cleaning,
            packageSizeText: "19.4 fl oz",
            stock: SampleStock(quantity: 0.2, initialQuantity: 1, purchasedDaysAgo: 40, expiresInDays: nil),
            purchases: [85, 40].map { SamplePurchase(daysAgo: $0, quantity: 1, priceCents: 347, store: "Walmart") },
            usages: [SampleUsage(daysAgo: 41, quantity: 1, type: .usedUp)]
        ),
        SampleProduct(
            name: "Laundry Detergent", brand: "Tide", category: .laundry, unit: .bottle, location: .cleaning,
            packageSizeText: "92 fl oz",
            stock: SampleStock(quantity: 1, initialQuantity: 1, purchasedDaysAgo: 22, expiresInDays: nil),
            purchases: [SamplePurchase(daysAgo: 22, quantity: 1, priceCents: 1397, store: "Target")],
            usages: []
        ),
        SampleProduct(
            name: "Toothpaste", brand: "Colgate", category: .personalCare, unit: .each, location: .bathroom,
            packageSizeText: "6 oz",
            stock: SampleStock(quantity: 1, initialQuantity: 1, purchasedDaysAgo: 25, expiresInDays: nil),
            purchases: [80, 25].map { SamplePurchase(daysAgo: $0, quantity: 1, priceCents: 299, store: "Walmart") },
            usages: [SampleUsage(daysAgo: 26, quantity: 1, type: .usedUp)]
        ),
    ]

    /// Purchases on a fixed cadence ending `lastDaysAgo` days ago.
    static func steady(
        every interval: Int,
        count: Int,
        lastDaysAgo: Int,
        quantity: Double,
        priceCents: Int?,
        store: String?
    ) -> [SamplePurchase] {
        (0..<count).map { index in
            SamplePurchase(daysAgo: lastDaysAgo + index * interval, quantity: quantity, priceCents: priceCents, store: store)
        }
    }
}
