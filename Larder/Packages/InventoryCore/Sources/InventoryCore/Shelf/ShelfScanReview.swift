import Foundation

/// One editable row on the shelf-scan review: either a new item to add or
/// a new count for an item already tracked.
public struct ShelfScanLine: Identifiable, Sendable, Hashable {
    public enum Action: Sendable, Hashable {
        case add
        case update
    }

    public let id: UUID
    public var include: Bool
    public var name: String
    public var brand: String
    public var category: ProductCategory
    /// How much is there now, in `unit`.
    public var quantity: Double
    public var unit: MeasureUnit
    /// A new opened container's full amount, when less than full is left.
    public var fullQuantity: Double?
    public var packageSize: String?
    public var shelfLifeDays: Int?
    public var confidence: ExtractionConfidence
    /// The tracked item this line updates.
    public var matchedItemID: UUID?
    /// The matched item's recorded amount before the scan.
    public var previousQuantity: Double?

    public init(
        id: UUID = UUID(),
        include: Bool = true,
        name: String,
        brand: String = "",
        category: ProductCategory,
        quantity: Double,
        unit: MeasureUnit,
        fullQuantity: Double? = nil,
        packageSize: String? = nil,
        shelfLifeDays: Int? = nil,
        confidence: ExtractionConfidence = .high,
        matchedItemID: UUID? = nil,
        previousQuantity: Double? = nil
    ) {
        self.id = id
        self.include = include
        self.name = name
        self.brand = brand
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.fullQuantity = fullQuantity
        self.packageSize = packageSize
        self.shelfLifeDays = shelfLifeDays
        self.confidence = confidence
        self.matchedItemID = matchedItemID
        self.previousQuantity = previousQuantity
    }

    public var action: Action { matchedItemID == nil ? .add : .update }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Updates may count down to zero (it's all gone); new items need an amount.
    public var isValid: Bool {
        switch action {
        case .add: !trimmedName.isEmpty && quantity > 0
        case .update: quantity >= 0
        }
    }

    /// How much more there is than was recorded (a restock), if any.
    public var increase: Double {
        guard let previousQuantity else { return 0 }
        return max(0, quantity - previousQuantity)
    }

    /// An item draft for adding this line. Expiry is estimated from Claude's
    /// shelf-life suggestion and marked as an estimate.
    public func draft(locationID: UUID?, date: Date, calendar: Calendar = .current) -> ItemDraft {
        var draft = ItemDraft(
            name: trimmedName,
            brand: brand,
            category: category,
            quantity: quantity,
            unit: unit,
            locationID: locationID,
            purchaseDate: date,
            packageSizeText: packageSize
        )
        if let shelfLifeDays, category.defaultTracksExpiry {
            draft.expiryDate = calendar.date(byAdding: .day, value: shelfLifeDays, to: date)
            draft.expiryIsEstimate = true
            draft.estimatedShelfLifeDays = shelfLifeDays
        }
        return draft
    }
}

/// The review of one shelf photo.
public struct ShelfScanReview: Sendable, Equatable {
    /// A tracked item at this location that wasn't in the photo. It may be
    /// out of frame, so nothing happens unless the user marks it finished.
    public struct UnseenItem: Identifiable, Sendable, Hashable {
        public var id: UUID { hint.itemID }
        public var hint: ShelfScanHint
        public var markFinished: Bool = false
    }

    public var lines: [ShelfScanLine]
    public var unseen: [UnseenItem]
    public var locationID: UUID?
    /// Log added items, and increases on tracked ones, as purchases made
    /// today, so they count toward usage estimates. Off for stock-taking.
    public var justBought: Bool = false

    /// Matches each detected product to a tracked item: first by the
    /// reference Claude gave (if it's real and unused), then by name when
    /// exactly one tracked item fits. Counts are converted to the tracked
    /// item's unit.
    public init(result: ShelfScanResult, hints: [ShelfScanHint], locationID: UUID?) {
        self.locationID = locationID
        let byRef = Dictionary(hints.map { ($0.ref.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var used = Set<UUID>()
        var lines: [ShelfScanLine] = []

        for item in result.items {
            var match: ShelfScanHint?
            if let ref = item.inventoryRef?.lowercased(), let hint = byRef[ref], !used.contains(hint.itemID) {
                match = hint
            } else {
                let candidates = hints.filter { !used.contains($0.itemID) && Self.sameProduct(item, $0) }
                if candidates.count == 1 { match = candidates[0] }
            }

            if let hint = match {
                used.insert(hint.itemID)
                let counted = Self.countedQuantity(item, as: hint)
                lines.append(ShelfScanLine(
                    name: hint.name,
                    brand: hint.brand ?? "",
                    category: item.category,
                    quantity: counted ?? hint.quantity,
                    unit: hint.unit,
                    packageSize: item.packageSize,
                    confidence: counted == nil ? .low : item.confidence,
                    matchedItemID: hint.itemID,
                    previousQuantity: hint.quantity
                ))
            } else {
                let left = Self.round(item.quantity * (item.fillLevel ?? 1))
                lines.append(ShelfScanLine(
                    name: item.name,
                    brand: item.brand ?? "",
                    category: item.category,
                    quantity: left > 0 ? left : item.quantity,
                    unit: item.unit,
                    fullQuantity: (item.fillLevel ?? 1) < 1 ? item.quantity : nil,
                    packageSize: item.packageSize,
                    shelfLifeDays: item.shelfLifeDays,
                    confidence: item.confidence
                ))
            }
        }
        self.lines = lines
        unseen = hints.filter { !used.contains($0.itemID) }.map { UnseenItem(hint: $0) }
    }

    public var includedLines: [ShelfScanLine] { lines.filter(\.include) }

    public var canImport: Bool {
        (!includedLines.isEmpty || unseen.contains(where: \.markFinished)) && includedLines.allSatisfy(\.isValid)
    }

    // MARK: - Matching

    /// Same normalized name (and brand, when both have one), or one name's
    /// words contained in the other's ("Potatoes" / "Russet Potatoes").
    static func sameProduct(_ item: ShelfScanItem, _ hint: ShelfScanHint) -> Bool {
        let itemBrand = TextNormalizer.key(item.brand ?? "")
        let hintBrand = TextNormalizer.key(hint.brand ?? "")
        if !itemBrand.isEmpty && !hintBrand.isEmpty && itemBrand != hintBrand { return false }
        if TextNormalizer.key(item.name) == TextNormalizer.key(hint.name) { return true }
        let itemTokens = Set(TextNormalizer.tokens(item.name))
        let hintTokens = Set(TextNormalizer.tokens(hint.name))
        guard !itemTokens.isEmpty, !hintTokens.isEmpty else { return false }
        return itemTokens.isSubset(of: hintTokens) || hintTokens.isSubset(of: itemTokens)
    }

    /// What's left of a tracked item, in its unit, or nil when the photo
    /// can't say (incompatible units and no fill level).
    static func countedQuantity(_ item: ShelfScanItem, as hint: ShelfScanHint) -> Double? {
        let fill = item.fillLevel ?? 1
        if let converted = item.unit.convert(item.quantity, to: hint.unit) {
            return round(converted * fill)
        }
        if item.unit.isDiscrete && hint.unit.isDiscrete {
            // "2 bags" of something tracked as "each", or the reverse.
            return round(item.quantity * fill)
        }
        if let fillLevel = item.fillLevel {
            return round(max(hint.initialQuantity, hint.quantity) * fillLevel)
        }
        return nil
    }

    static func round(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
