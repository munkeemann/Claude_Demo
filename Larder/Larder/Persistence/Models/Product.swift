import Foundation
import InventoryCore
import SwiftData

/// A canonical product ("Great Value Whole Milk, 1 gal"). Inventory items,
/// purchases, usage events and aliases all hang off a product.
///
/// CloudKit rules apply to every model: all stored properties have defaults,
/// relationships are optional with inverses, and there are no unique
/// constraints. Enums are stored as raw strings.
@Model
final class Product {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String?
    var categoryRaw: String = "other"
    var defaultUnitRaw: String = "each"
    var packageSizeText: String?
    var imageURLString: String?
    /// Per-product shelf-life overrides in days, keyed by storage climate.
    var shelfLifeRoomDays: Int?
    var shelfLifeFridgeDays: Int?
    var shelfLifeFreezerDays: Int?
    var isIngredient: Bool = false
    var tracksRunOut: Bool = true
    var tracksExpiry: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \InventoryItem.product)
    var items: [InventoryItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \PurchaseEvent.product)
    var purchases: [PurchaseEvent]? = []

    @Relationship(deleteRule: .cascade, inverse: \UsageEvent.product)
    var usages: [UsageEvent]? = []

    @Relationship(deleteRule: .cascade, inverse: \ProductAlias.product)
    var aliases: [ProductAlias]? = []

    @Relationship(deleteRule: .nullify, inverse: \ShoppingListItem.product)
    var shoppingItems: [ShoppingListItem]? = []

    init(name: String, brand: String? = nil, category: ProductCategory, now: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.brand = brand
        self.categoryRaw = category.rawValue
        self.defaultUnitRaw = category.defaultUnit.rawValue
        self.isIngredient = category.defaultIsIngredient
        self.tracksRunOut = category.defaultTracksRunOut
        self.tracksExpiry = category.defaultTracksExpiry
        self.createdAt = now
        self.updatedAt = now
    }

    var category: ProductCategory {
        get { ProductCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var defaultUnit: MeasureUnit {
        get { MeasureUnit(rawValue: defaultUnitRaw) ?? .each }
        set { defaultUnitRaw = newValue.rawValue }
    }

    var imageURL: URL? {
        get { imageURLString.flatMap(URL.init(string:)) }
        set { imageURLString = newValue?.absoluteString }
    }

    var displayName: String {
        name.isEmpty ? "Unnamed product" : name
    }

    /// Shelf-life override for a climate, if one is set.
    func shelfLifeDays(for climate: StorageClimate) -> Int? {
        switch climate {
        case .room: shelfLifeRoomDays
        case .fridge: shelfLifeFridgeDays
        case .freezer: shelfLifeFreezerDays
        }
    }

    var barcodes: [String] {
        (aliases ?? []).filter { $0.kind == .barcode }.map(\.value)
    }
}
