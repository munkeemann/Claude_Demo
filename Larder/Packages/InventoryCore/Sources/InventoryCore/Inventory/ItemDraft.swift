import Foundation

/// Form state for adding or editing an inventory item, independent of
/// persistence. The app turns a validated draft into SwiftData records.
public struct ItemDraft: Sendable, Hashable {
    public var name: String
    public var brand: String
    public var category: ProductCategory
    public var quantity: Double
    public var unit: MeasureUnit
    public var locationID: UUID?
    public var purchaseDate: Date
    public var expiryDate: Date?
    public var notes: String
    public var barcode: String?
    public var packageSizeText: String?
    public var imageURL: URL?
    public var priceCents: Int?
    public var isIngredient: Bool
    public var tracksRunOut: Bool
    public var tracksExpiry: Bool

    public init(
        name: String = "",
        brand: String = "",
        category: ProductCategory = .other,
        quantity: Double = 1,
        unit: MeasureUnit? = nil,
        locationID: UUID? = nil,
        purchaseDate: Date = Date(),
        expiryDate: Date? = nil,
        notes: String = "",
        barcode: String? = nil,
        packageSizeText: String? = nil,
        imageURL: URL? = nil,
        priceCents: Int? = nil,
        isIngredient: Bool? = nil,
        tracksRunOut: Bool? = nil,
        tracksExpiry: Bool? = nil
    ) {
        self.name = name
        self.brand = brand
        self.category = category
        self.quantity = quantity
        self.unit = unit ?? category.defaultUnit
        self.locationID = locationID
        self.purchaseDate = purchaseDate
        self.expiryDate = expiryDate
        self.notes = notes
        self.barcode = barcode
        self.packageSizeText = packageSizeText
        self.imageURL = imageURL
        self.priceCents = priceCents
        self.isIngredient = isIngredient ?? category.defaultIsIngredient
        self.tracksRunOut = tracksRunOut ?? category.defaultTracksRunOut
        self.tracksExpiry = tracksExpiry ?? category.defaultTracksExpiry
    }

    /// Builds a draft from a barcode lookup. Packaged goods are counted by
    /// package; the package size is kept for display.
    public init(lookup: ProductLookupResult, purchaseDate: Date = Date()) {
        self.init(
            name: lookup.name,
            brand: lookup.brand ?? "",
            category: lookup.category,
            quantity: 1,
            unit: .each,
            purchaseDate: purchaseDate,
            barcode: lookup.barcode,
            packageSizeText: lookup.packageSize?.label ?? lookup.packageSizeText,
            imageURL: lookup.imageURL
        )
    }

    /// Resets the category-derived flags and unit after the category changes.
    public mutating func applyCategoryDefaults() {
        unit = category.defaultUnit
        isIngredient = category.defaultIsIngredient
        tracksRunOut = category.defaultTracksRunOut
        tracksExpiry = category.defaultTracksExpiry
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedBrand: String? {
        let value = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public enum Issue: Hashable, Sendable {
        case missingName
        case nonPositiveQuantity
        case expiryBeforePurchase
    }

    public var issues: [Issue] {
        var result: [Issue] = []
        if trimmedName.isEmpty { result.append(.missingName) }
        if !(quantity > 0) { result.append(.nonPositiveQuantity) }
        if let expiryDate, expiryDate < Calendar.current.startOfDay(for: purchaseDate) {
            result.append(.expiryBeforePurchase)
        }
        return result
    }

    public var isValid: Bool { issues.isEmpty }
}

extension ItemDraft.Issue {
    public var message: String {
        switch self {
        case .missingName: "Enter a name."
        case .nonPositiveQuantity: "Quantity must be more than zero."
        case .expiryBeforePurchase: "Expiry date is before the purchase date."
        }
    }
}
