import Foundation

/// A canned shelf scan of a pantry shelf, for previews, tests and the
/// offline demo. It lines up with `SampleData` so the demo shows both new
/// items and updated counts.
public enum SampleShelfScan {
    public static let result = ShelfScanResult(areas: [
        "Top shelf: bag of russet potatoes, 4 yellow onions",
        "Middle shelf: open bag of jasmine rice, 2 boxes of spaghetti, 3 cans of diced tomatoes",
        "Bottom shelf: half-empty jar of peanut butter",
    ], items: [
        ShelfScanItem(name: "Russet Potatoes", category: .produce, quantity: 1, unit: .bag, packageSize: "5 lb", shelfLifeDays: 21),
        ShelfScanItem(name: "Yellow Onions", category: .produce, quantity: 4, unit: .each, shelfLifeDays: 30),
        ShelfScanItem(name: "Jasmine Rice", brand: "Mahatma", category: .grains, quantity: 1, unit: .bag, packageSize: "5 lb", fillLevel: 0.4),
        ShelfScanItem(name: "Spaghetti", brand: "Barilla", category: .grains, quantity: 2, unit: .box, packageSize: "16 oz"),
        ShelfScanItem(name: "Diced Tomatoes", brand: "Hunt's", category: .canned, quantity: 3, unit: .can, packageSize: "14.5 oz"),
        ShelfScanItem(name: "Peanut Butter", brand: "Jif", category: .condiments, quantity: 1, unit: .jar, packageSize: "16 oz", fillLevel: 0.5, confidence: .medium),
    ], place: .room)
}
