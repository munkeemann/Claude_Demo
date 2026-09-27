import Foundation

/// Whether scanned-out items were thrown away or finished.
public enum ScanOutDisposition: String, Codable, CaseIterable, Sendable, Identifiable {
    case tossed
    case used

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .tossed: "Tossed"
        case .used: "Used up"
        }
    }
}

/// Photos of things leaving the house, with the household's inventory to
/// match them against.
public struct ScanOutInput: Sendable, Equatable {
    public var images: [Data]
    public var disposition: ScanOutDisposition
    /// Every in-stock item, across locations.
    public var hints: [ShelfScanHint]

    public init(images: [Data], disposition: ScanOutDisposition, hints: [ShelfScanHint]) {
        self.images = images.filter { !$0.isEmpty }
        self.disposition = disposition
        self.hints = hints
    }
}

/// One product Claude sees being thrown out or finished.
public struct ScanOutItem: Codable, Sendable, Hashable {
    public var name: String
    public var brand: String?
    /// The inventory reference ("i3") it is, when clear.
    public var inventoryRef: String?
    /// True when all of it is going; false when only part of it is.
    public var isAll: Bool
    /// For part of something: how much is going, in `unit`.
    public var quantity: Double?
    public var unit: MeasureUnit?
    public var confidence: ExtractionConfidence

    public init(
        name: String,
        brand: String? = nil,
        inventoryRef: String? = nil,
        isAll: Bool = true,
        quantity: Double? = nil,
        unit: MeasureUnit? = nil,
        confidence: ExtractionConfidence = .high
    ) {
        self.name = name
        self.brand = brand
        self.inventoryRef = inventoryRef
        self.isAll = isAll
        self.quantity = quantity
        self.unit = unit
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case name, brand, inventoryRef, isAll, quantity, unit, confidence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand).flatMap { $0.isEmpty ? nil : $0 }
        inventoryRef = try container.decodeIfPresent(String.self, forKey: .inventoryRef).flatMap { $0.isEmpty ? nil : $0 }
        isAll = (try? container.decode(Bool.self, forKey: .isAll)) ?? true
        quantity = (try? container.decodeIfPresent(Double.self, forKey: .quantity)).flatMap { $0 > 0 ? $0 : nil }
        unit = try? container.decodeIfPresent(MeasureUnit.self, forKey: .unit)
        confidence = (try? container.decode(ExtractionConfidence.self, forKey: .confidence)) ?? .medium
    }
}

public struct ScanOutResult: Codable, Sendable, Equatable {
    public var items: [ScanOutItem]

    public init(items: [ScanOutItem]) {
        self.items = items
    }
}

public enum ScanOutSchema {
    public static let schema: JSONValue = JSONSchema.object([
        ("items", JSONSchema.array(of: item, description: "Every distinct product in the photos, once each.")),
    ])

    static let item: JSONValue = JSONSchema.object([
        ("name", JSONSchema.string("Everyday product name without brand or size.")),
        ("brand", JSONSchema.nullable(JSONSchema.string())),
        ("inventoryRef", JSONSchema.nullable(JSONSchema.string("Reference of the matching inventory item (e.g. 'i3'); null when none fits."))),
        ("isAll", JSONSchema.boolean("True when all of it is going. False only when clearly part of it is kept.")),
        ("quantity", JSONSchema.nullable(JSONSchema.number("When isAll is false: how much is going, in unit."))),
        ("unit", JSONSchema.nullable(JSONSchema.enumeration(MeasureUnit.allCases.map(\.rawValue)))),
        ("confidence", JSONSchema.enumeration(ExtractionConfidence.allCases.map(\.rawValue))),
    ])
}

public enum ScanOutPrompt {
    public static let system = """
    You help a household keep its home inventory current. You get photos of food and household goods \
    that are leaving the house: thrown away (spoiled, expired, leftovers) or used up (empty packages \
    headed for the recycling). You also get the household's current inventory, each item with a short \
    reference like "i3".

    Rules:
    - List every distinct product you can see, once, even if it appears in several photos. Include \
    empty or crushed packages, loose produce and containers of leftovers.
    - Match each product to the inventory item it is and set inventoryRef. Use the name, brand, \
    package and where it's kept. Never use one reference twice; when two items could fit, pick the \
    one expiring soonest. Leave inventoryRef null when nothing fits.
    - isAll is true unless the photo clearly shows only part of it going (half a bag of spinach being \
    emptied into the trash while the rest is kept). Then set quantity and unit for the part that goes.
    - confidence: "high" when the label or shape is unmistakable, "low" when you're guessing.
    """

    public static func userText(for input: ScanOutInput) -> String {
        var sections: [String] = []
        let verb = input.disposition == .tossed ? "being thrown away" : "used up"
        sections.append(input.images.count > 1
            ? "These \(input.images.count) photos show things \(verb). Count each product once."
            : "This photo shows things \(verb).")
        if input.hints.isEmpty {
            sections.append("The inventory is empty; leave every inventoryRef null.")
        } else {
            let lines = input.hints.map { hint -> String in
                var line = "- \(hint.ref): \(hint.name)"
                if let brand = hint.brand { line += " (\(brand))" }
                line += ", \(hint.unit.label(for: hint.quantity))"
                if let place = hint.locationName { line += ", \(place)" }
                return line
            }
            sections.append("Inventory:\n" + lines.joined(separator: "\n"))
        }
        sections.append("List what's in the photos.")
        return sections.joined(separator: "\n\n")
    }
}

/// One row on the scan-out review.
public struct ScanOutLine: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var include: Bool
    /// What Claude called it.
    public var name: String
    public var matchedItemID: UUID?
    public var disposition: ScanOutDisposition
    /// nil means all of it; otherwise how much, in the matched item's unit.
    public var amount: Double?
    public var confidence: ExtractionConfidence

    public init(
        id: UUID = UUID(),
        include: Bool = true,
        name: String,
        matchedItemID: UUID? = nil,
        disposition: ScanOutDisposition,
        amount: Double? = nil,
        confidence: ExtractionConfidence = .high
    ) {
        self.id = id
        self.include = include
        self.name = name
        self.matchedItemID = matchedItemID
        self.disposition = disposition
        self.amount = amount
        self.confidence = confidence
    }

    /// The action to apply to the matched item.
    public var action: QuickAction {
        switch (disposition, amount) {
        case (.tossed, nil): .tossed
        case (.tossed, let amount?): .tossedSome(amount)
        case (.used, nil): .usedUp
        case (.used, let amount?): .usedSome(amount)
        }
    }
}

/// The review of a scan-out: which inventory items leave, and how.
public struct ScanOutReview: Sendable, Equatable {
    public var lines: [ScanOutLine]

    /// Matches each product to an unused inventory item, by Claude's
    /// reference or else a unique name match. Products that match nothing
    /// start unticked: there's nothing to remove until the person picks an item.
    public init(result: ScanOutResult, hints: [ShelfScanHint], disposition: ScanOutDisposition) {
        let byRef = Dictionary(hints.map { ($0.ref.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var used = Set<UUID>()
        var lines: [ScanOutLine] = []
        for item in result.items {
            var match: ShelfScanHint?
            if let ref = item.inventoryRef?.lowercased(), let hint = byRef[ref], !used.contains(hint.itemID) {
                match = hint
            } else {
                let asShelfItem = ShelfScanItem(name: item.name, brand: item.brand, category: .other, quantity: 1, unit: .each)
                let candidates = hints.filter { !used.contains($0.itemID) && ShelfScanReview.sameProduct(asShelfItem, $0) }
                if candidates.count == 1 { match = candidates[0] }
            }
            if let match { used.insert(match.itemID) }
            lines.append(ScanOutLine(
                include: match != nil,
                name: item.name,
                matchedItemID: match?.itemID,
                disposition: disposition,
                amount: match.flatMap { Self.partAmount(item, of: $0) },
                confidence: item.confidence
            ))
        }
        self.lines = lines
    }

    public var includedLines: [ScanOutLine] {
        lines.filter { $0.include && $0.matchedItemID != nil }
    }

    public var canApply: Bool { !includedLines.isEmpty }

    /// Sets every line to tossed or used.
    public mutating func setDisposition(_ disposition: ScanOutDisposition) {
        for index in lines.indices { lines[index].disposition = disposition }
    }

    /// The part going, in the item's unit, or nil for all of it.
    static func partAmount(_ item: ScanOutItem, of hint: ShelfScanHint) -> Double? {
        guard !item.isAll, let quantity = item.quantity else { return nil }
        let unit = item.unit ?? hint.unit
        let converted = unit.convert(quantity, to: hint.unit) ?? (unit.isDiscrete && hint.unit.isDiscrete ? quantity : nil)
        guard let converted, converted > 0 else { return nil }
        return converted < hint.quantity ? ShelfScanReview.round(converted) : nil
    }
}
