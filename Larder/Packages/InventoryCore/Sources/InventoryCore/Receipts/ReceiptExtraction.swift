import Foundation

/// Structured receipt data returned by Claude. Field names match the JSON
/// schema below; money amounts are decimal (the app converts to cents).
public struct ReceiptExtraction: Codable, Sendable, Equatable {
    public var storeName: String?
    /// ISO-8601 date ("2026-09-21"), or nil if not printed.
    public var purchaseDate: String?
    /// ISO 4217 code if it can be inferred ("USD").
    public var currency: String?
    public var items: [ReceiptLineItem]
    public var subtotal: Double?
    public var tax: Double?
    public var total: Double?

    public init(
        storeName: String? = nil,
        purchaseDate: String? = nil,
        currency: String? = nil,
        items: [ReceiptLineItem],
        subtotal: Double? = nil,
        tax: Double? = nil,
        total: Double? = nil
    ) {
        self.storeName = storeName
        self.purchaseDate = purchaseDate
        self.currency = currency
        self.items = items
        self.subtotal = subtotal
        self.tax = tax
        self.total = total
    }
}

public enum ExtractionConfidence: String, Codable, Sendable, CaseIterable {
    case high
    case medium
    case low
}

public struct ReceiptLineItem: Codable, Sendable, Hashable {
    /// The item text exactly as printed, without price, item code or tax flag.
    public var rawText: String
    /// Normalized, human-readable product name ("Whole Milk").
    public var name: String
    public var brand: String?
    public var category: ProductCategory
    public var quantity: Double
    public var unit: MeasureUnit
    /// Size of one package if printed or implied ("1 gal", "16 oz").
    public var packageSize: String?
    /// Line total after any discounts that apply to it.
    public var totalPrice: Double?
    public var location: LocationKind
    /// Typical days until it spoils at `location`, for perishables.
    public var shelfLifeDays: Int?
    public var confidence: ExtractionConfidence

    public init(
        rawText: String,
        name: String,
        brand: String? = nil,
        category: ProductCategory,
        quantity: Double,
        unit: MeasureUnit,
        packageSize: String? = nil,
        totalPrice: Double? = nil,
        location: LocationKind,
        shelfLifeDays: Int? = nil,
        confidence: ExtractionConfidence = .high
    ) {
        self.rawText = rawText
        self.name = name
        self.brand = brand
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.packageSize = packageSize
        self.totalPrice = totalPrice
        self.location = location
        self.shelfLifeDays = shelfLifeDays
        self.confidence = confidence
    }

    /// Decodes leniently: an unknown category, unit or location from the model
    /// degrades to a safe default instead of failing the whole receipt.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawText = try container.decode(String.self, forKey: .rawText)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand).flatMap { $0.isEmpty ? nil : $0 }
        category = (try? container.decode(ProductCategory.self, forKey: .category)) ?? .other
        quantity = (try? container.decode(Double.self, forKey: .quantity)).flatMap { $0 > 0 ? $0 : nil } ?? 1
        unit = (try? container.decode(MeasureUnit.self, forKey: .unit)) ?? .each
        packageSize = try container.decodeIfPresent(String.self, forKey: .packageSize).flatMap { $0.isEmpty ? nil : $0 }
        totalPrice = try? container.decodeIfPresent(Double.self, forKey: .totalPrice)
        location = (try? container.decode(LocationKind.self, forKey: .location)) ?? category.defaultLocationKind
        let days = (try? container.decodeIfPresent(Int.self, forKey: .shelfLifeDays))
            ?? (try? container.decodeIfPresent(Double.self, forKey: .shelfLifeDays)).map { Int($0.rounded()) }
        shelfLifeDays = days.flatMap { $0 > 0 ? $0 : nil }
        confidence = (try? container.decode(ExtractionConfidence.self, forKey: .confidence)) ?? .medium
    }
}

// MARK: - Schema

public enum ReceiptExtractionSchema {
    /// Locations Claude may suggest; custom locations are the user's to pick.
    static let locations = LocationKind.builtIn.map(\.rawValue)

    public static let schema: JSONValue = JSONSchema.object([
        ("storeName", JSONSchema.nullable(JSONSchema.string("Store or merchant name as printed, title-cased."))),
        ("purchaseDate", JSONSchema.nullable(JSONSchema.string("Purchase date as YYYY-MM-DD, or null if not printed."))),
        ("currency", JSONSchema.nullable(JSONSchema.string("ISO 4217 currency code, e.g. USD."))),
        ("items", JSONSchema.array(of: lineItem, description: "Purchased products, one per distinct product.")),
        ("subtotal", JSONSchema.nullable(JSONSchema.number("Subtotal before tax, as printed."))),
        ("tax", JSONSchema.nullable(JSONSchema.number("Total tax, as printed."))),
        ("total", JSONSchema.nullable(JSONSchema.number("Grand total, as printed."))),
    ])

    static let lineItem: JSONValue = JSONSchema.object([
        ("rawText", JSONSchema.string("Item description exactly as printed, without price, item code, or tax flags.")),
        ("name", JSONSchema.string("Expanded, human-readable product name without brand or size, e.g. 'Whole Milk'.")),
        ("brand", JSONSchema.nullable(JSONSchema.string("Brand if identifiable (store brands too, e.g. 'Great Value')."))),
        ("category", JSONSchema.enumeration(ProductCategory.allCases.map(\.rawValue))),
        ("quantity", JSONSchema.number("Amount bought, in `unit`.")),
        ("unit", JSONSchema.enumeration(MeasureUnit.allCases.map(\.rawValue))),
        ("packageSize", JSONSchema.nullable(JSONSchema.string("Size of one package, e.g. '1 gal', '16 oz', '12 rolls'."))),
        ("totalPrice", JSONSchema.nullable(JSONSchema.number("Line total after discounts that apply to this item."))),
        ("location", JSONSchema.enumeration(locations)),
        ("shelfLifeDays", JSONSchema.nullable(JSONSchema.integer("Typical days until spoiled at `location` for perishables; null for shelf-stable and household goods."))),
        ("confidence", JSONSchema.enumeration(ExtractionConfidence.allCases.map(\.rawValue))),
    ])
}
