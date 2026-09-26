import Foundation

/// What Claude sees in a photo of a shelf, fridge or cupboard.
public struct ShelfScanResult: Codable, Sendable, Equatable {
    /// Claude's walk through the photo, one line per shelf, door shelf or
    /// bin, written before `items` so nothing gets skipped.
    public var areas: [String]
    public var items: [ShelfScanItem]
    /// The kind of storage the photo shows, when it's clear.
    public var place: StorageClimate?

    public init(areas: [String] = [], items: [ShelfScanItem], place: StorageClimate? = nil) {
        self.areas = areas
        self.items = items
        self.place = place
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        areas = (try? container.decodeIfPresent([String].self, forKey: .areas)) ?? []
        items = try container.decode([ShelfScanItem].self, forKey: .items)
        place = try? container.decodeIfPresent(StorageClimate.self, forKey: .place)
    }

    /// Where the photo seems to be, when that's a different kind of storage
    /// from the location the person picked.
    public func mismatchedPlace(comparedTo climate: StorageClimate?) -> StorageClimate? {
        guard let place, let climate, place != climate else { return nil }
        return place
    }
}

/// One distinct product in the photo, with how much of it there is.
public struct ShelfScanItem: Codable, Sendable, Hashable {
    /// Everyday product name without brand or size ("Russet Potatoes").
    public var name: String
    public var brand: String?
    public var category: ProductCategory
    /// How much is there, in `unit`: a count of packages or pieces, or a
    /// weight or volume for loose goods.
    public var quantity: Double
    public var unit: MeasureUnit
    /// Size of one package if visible or obvious ("5 lb", "64 fl oz").
    public var packageSize: String?
    /// For a single opened container: roughly how full it is (0–1). The
    /// quantity then describes the full container.
    public var fillLevel: Double?
    /// The inventory reference ("i3") this is, when it's clearly the same
    /// product as one already tracked at this location.
    public var inventoryRef: String?
    /// Typical days until it spoils where it's kept, for perishables.
    public var shelfLifeDays: Int?
    public var confidence: ExtractionConfidence

    public init(
        name: String,
        brand: String? = nil,
        category: ProductCategory,
        quantity: Double,
        unit: MeasureUnit,
        packageSize: String? = nil,
        fillLevel: Double? = nil,
        inventoryRef: String? = nil,
        shelfLifeDays: Int? = nil,
        confidence: ExtractionConfidence = .high
    ) {
        self.name = name
        self.brand = brand
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.packageSize = packageSize
        self.fillLevel = fillLevel
        self.inventoryRef = inventoryRef
        self.shelfLifeDays = shelfLifeDays
        self.confidence = confidence
    }

    /// Decodes leniently, like receipt lines: an unknown category or unit
    /// degrades to a safe default instead of failing the whole scan.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand).flatMap { $0.isEmpty ? nil : $0 }
        category = (try? container.decode(ProductCategory.self, forKey: .category)) ?? .other
        quantity = (try? container.decode(Double.self, forKey: .quantity)).flatMap { $0 > 0 ? $0 : nil } ?? 1
        unit = (try? container.decode(MeasureUnit.self, forKey: .unit)) ?? .each
        packageSize = try container.decodeIfPresent(String.self, forKey: .packageSize).flatMap { $0.isEmpty ? nil : $0 }
        fillLevel = (try? container.decodeIfPresent(Double.self, forKey: .fillLevel)).map { min(max($0, 0), 1) }
        inventoryRef = try container.decodeIfPresent(String.self, forKey: .inventoryRef).flatMap { $0.isEmpty ? nil : $0 }
        let days = (try? container.decodeIfPresent(Int.self, forKey: .shelfLifeDays))
            ?? (try? container.decodeIfPresent(Double.self, forKey: .shelfLifeDays)).map { Int($0.rounded()) }
        shelfLifeDays = days.flatMap { $0 > 0 ? $0 : nil }
        confidence = (try? container.decode(ExtractionConfidence.self, forKey: .confidence)) ?? .medium
    }
}

/// An item already tracked at the scanned location, offered to Claude by a
/// short reference so it can say "this is i3" instead of guessing by name.
public struct ShelfScanHint: Sendable, Hashable, Identifiable {
    public var id: UUID { itemID }
    public var ref: String
    public var itemID: UUID
    public var name: String
    public var brand: String?
    public var quantity: Double
    public var initialQuantity: Double
    public var unit: MeasureUnit

    public init(ref: String, itemID: UUID, name: String, brand: String?, quantity: Double, initialQuantity: Double, unit: MeasureUnit) {
        self.ref = ref
        self.itemID = itemID
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.initialQuantity = initialQuantity
        self.unit = unit
    }
}

public struct ShelfScanInput: Sendable, Equatable {
    /// A JPEG, already downscaled to what the model can use.
    public var image: Data
    public var locationName: String?
    public var climate: StorageClimate?
    public var hints: [ShelfScanHint]

    public init(image: Data, locationName: String? = nil, climate: StorageClimate? = nil, hints: [ShelfScanHint] = []) {
        self.image = image
        self.locationName = locationName
        self.climate = climate
        self.hints = hints
    }
}

// MARK: - Schema

public enum ShelfScanSchema {
    /// Requests are sent with sorted keys, so Claude writes `areas` before
    /// `items`: it takes stock of each part of the photo, then lists.
    public static let schema: JSONValue = JSONSchema.object([
        ("areas", JSONSchema.array(
            of: JSONSchema.string(),
            description: "One line per area of the photo (each shelf, door shelf, drawer or bin; top to bottom, left to right) naming everything in it, e.g. 'Top door shelf: ketchup, yellow mustard, 2 hot sauces, soy sauce'."
        )),
        ("items", JSONSchema.array(of: item, description: "Every distinct product from areas, one entry per product.")),
        ("place", JSONSchema.nullable(JSONSchema.enumeration(
            StorageClimate.allCases.map(\.rawValue),
            description: "What the photo shows: 'fridge', 'freezer', or 'room' for a pantry, cupboard or shelf. Null if unclear."
        ))),
    ])

    static let item: JSONValue = JSONSchema.object([
        ("name", JSONSchema.string("Everyday product name without brand or size, e.g. 'Russet Potatoes', 'Whole Milk'.")),
        ("brand", JSONSchema.nullable(JSONSchema.string("Brand if the label is readable; null for loose produce."))),
        ("category", JSONSchema.enumeration(ProductCategory.allCases.map(\.rawValue))),
        ("quantity", JSONSchema.number("How much is there, in `unit`.")),
        ("unit", JSONSchema.enumeration(MeasureUnit.allCases.map(\.rawValue))),
        ("packageSize", JSONSchema.nullable(JSONSchema.string("Size of one package if visible or obvious, e.g. '5 lb', '64 fl oz'."))),
        ("fillLevel", JSONSchema.nullable(JSONSchema.number("For one opened or see-through container: fraction left, 0 to 1, with quantity/unit describing the full container. Null otherwise."))),
        ("inventoryRef", JSONSchema.nullable(JSONSchema.string("Reference of the matching inventory item (e.g. 'i3') when it is clearly the same product; otherwise null."))),
        ("shelfLifeDays", JSONSchema.nullable(JSONSchema.integer("Typical days until spoiled where it's kept, for perishables; null for shelf-stable and household goods."))),
        ("confidence", JSONSchema.enumeration(ExtractionConfidence.allCases.map(\.rawValue))),
    ])
}

// MARK: - Prompt

public enum ShelfScanPrompt {
    /// Stable instructions; the per-scan details go in the user message.
    public static let system = """
    You take stock of a household's food and household goods from a photo of a shelf, pantry, \
    fridge, freezer or cupboard, for a home inventory app. The result replaces typing everything \
    in by hand. The person checks every entry before anything is saved and can untick a wrong \
    guess in one tap, but has to type in anything you miss, so be thorough: list everything.

    How to look:
    - Fill in areas first. Go over the photo one area at a time (each shelf, door shelf, drawer \
    and bin, top to bottom, left to right) and name everything in it, including things at the \
    edges, behind other things, lying down, or only partly in frame. Then write items from those \
    notes: everything named in areas belongs in items.
    - Fridge doors and small shelves are crowded. Expect many bottles, jars and tubs of \
    condiments, sauces, dressings, spreads and drinks, and check each one.

    What to list:
    - Every food, drink and household consumable: packaged goods, loose and bagged produce, \
    condiments and sauces, jars, bottles, cartons, tubs, butter, eggs, leftovers, drinks.
    - Skip only the fixtures: shelves, bins, the appliance itself, magnets and decorations.
    - A container you can't read: name it from what it looks like (a small bottle of red sauce \
    is probably hot sauce, a clear tub of chunky red dip "Salsa", a foil-wrapped stick "Butter", \
    a takeout container "Leftovers") with confidence "low". Never leave something out because \
    you're unsure what it is.
    - One entry per distinct product. Identical packages side by side are one entry with a \
    count; different flavors, varieties or brands are separate entries.

    Amounts:
    - quantity/unit: choose what makes consumption easy to track.
      - Packaged goods: the number of packages with the container word (can, jar, box, bag, \
    bottle, pack, roll) or "each", and the size of one package in packageSize.
      - Loose produce you can count (potatoes, apples, onions, lemons): the count, unit "each".
      - Produce in a bag (a sack of potatoes): quantity 1, unit "bag", and the bag's weight in \
    packageSize if printed.
      - Milk and juice jugs: the volume ("gal", "qt", "fl oz") when the size is standard.
    - fillLevel: only for a single opened or see-through container (a half-empty milk jug, a \
    jar of peanut butter). Then quantity/unit describe the full container: a 1-gallon jug that's \
    half full is quantity 1, unit "gal", fillLevel 0.5. Null for sealed packages and counts.
    - Items partly hidden: count what's visible.

    Other fields:
    - confidence: "high" when the label or shape is unmistakable, "medium" when you're fairly \
    sure, "low" when you're guessing or the item is mostly hidden.
    - shelfLifeDays: for perishable food, typical days until it spoils where the photo shows it \
    kept, unopened. Null for shelf-stable food and household goods.
    - place: the kind of storage in the photo, which may differ from the location the person \
    picked. List everything either way.
    - If "Already tracked here" lists items, they are this household's inventory at the picked \
    location. When an entry is clearly the same product as one of them, set inventoryRef to its \
    reference and report how much is there now, in that item's unit when you can. Never reuse a \
    reference for two entries. Leave inventoryRef null when unsure. Tracked items that aren't in \
    the photo are fine to leave out; the list never limits what you report.
    """

    /// The text that follows the image.
    public static func userText(for input: ShelfScanInput) -> String {
        var sections: [String] = []
        if let name = input.locationName {
            var place = "Picked location: \(name)"
            if let climate = input.climate { place += " (\(climate.rawValue) temperature)" }
            sections.append(place + ".")
        }
        if !input.hints.isEmpty {
            let lines = input.hints.map { hint -> String in
                let brand = hint.brand.map { " (\($0))" } ?? ""
                return "- \(hint.ref): \(hint.name)\(brand), last recorded \(hint.unit.label(for: hint.quantity)), unit \(hint.unit.rawValue)"
            }
            sections.append("Already tracked here:\n" + lines.joined(separator: "\n"))
        }
        sections.append("Take stock of everything in the photo.")
        return sections.joined(separator: "\n\n")
    }

    /// Short references ("i1", "i2", …) for the items at a location.
    public static func hints(
        for items: [(id: UUID, name: String, brand: String?, quantity: Double, initialQuantity: Double, unit: MeasureUnit)]
    ) -> [ShelfScanHint] {
        items.enumerated().map { index, item in
            ShelfScanHint(
                ref: "i\(index + 1)",
                itemID: item.id,
                name: item.name,
                brand: item.brand,
                quantity: item.quantity,
                initialQuantity: item.initialQuantity,
                unit: item.unit
            )
        }
    }
}
