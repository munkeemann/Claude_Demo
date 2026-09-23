import Foundation

/// One editable row on the receipt review screen.
public struct ReceiptReviewLine: Identifiable, Sendable, Hashable {
    public enum Origin: String, Sendable {
        /// Straight from Claude's extraction.
        case extracted
        /// Name/brand/category came from a remembered correction.
        case remembered
    }

    public let id: UUID
    public var include: Bool
    public var rawText: String
    public var name: String
    public var brand: String
    public var category: ProductCategory
    public var quantity: Double
    public var unit: MeasureUnit
    public var packageSize: String?
    public var priceCents: Int?
    public var locationKind: LocationKind
    /// The chosen storage location; the app maps `locationKind` to its
    /// built-in location initially, and the user can pick any location.
    public var locationID: UUID?
    public var shelfLifeDays: Int?
    public var confidence: ExtractionConfidence
    /// An existing product this line maps to, if known.
    public var matchedProductID: UUID?
    public var origin: Origin

    /// The values before any edits, used to detect corrections.
    public let original: Snapshot

    public struct Snapshot: Sendable, Hashable {
        public var name: String
        public var brand: String
        public var category: ProductCategory
        public var unit: MeasureUnit
    }

    public init(item: ReceiptLineItem, hint: ReceiptHint?, id: UUID = UUID()) {
        self.id = id
        include = true
        rawText = item.rawText
        name = hint?.name ?? item.name
        brand = hint.map { $0.brand ?? "" } ?? (item.brand ?? "")
        category = hint?.category ?? item.category
        quantity = item.quantity
        unit = item.unit
        packageSize = item.packageSize
        priceCents = ReceiptText.cents(item.totalPrice)
        locationKind = item.location
        shelfLifeDays = item.shelfLifeDays
        confidence = hint == nil ? item.confidence : .high
        matchedProductID = hint?.productID
        origin = hint == nil ? .extracted : .remembered
        original = Snapshot(name: name, brand: brand, category: category, unit: unit)
    }

    public var aliasKey: String { ReceiptText.key(rawText) }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Whether the user changed what product this line is.
    public var wasCorrected: Bool {
        TextNormalizer.key(name) != TextNormalizer.key(original.name)
            || TextNormalizer.key(brand) != TextNormalizer.key(original.brand)
            || category != original.category
    }

    public var isValid: Bool { !trimmedName.isEmpty && quantity > 0 }

    /// Converts the line to an item draft. Expiry is estimated from Claude's
    /// shelf-life suggestion and marked as an estimate.
    public func draft(purchaseDate: Date, calendar: Calendar = .current) -> ItemDraft {
        var draft = ItemDraft(
            name: trimmedName,
            brand: brand,
            category: category,
            quantity: quantity,
            unit: unit,
            locationID: locationID,
            purchaseDate: purchaseDate,
            packageSizeText: packageSize,
            priceCents: priceCents
        )
        if let shelfLifeDays, category.defaultTracksExpiry {
            draft.expiryDate = calendar.date(byAdding: .day, value: shelfLifeDays, to: purchaseDate)
            draft.expiryIsEstimate = true
            draft.estimatedShelfLifeDays = shelfLifeDays
        }
        return draft
    }
}

/// The whole review: header fields plus editable lines.
public struct ReceiptReview: Sendable, Equatable {
    public var storeName: String
    public var purchaseDate: Date
    public var currencyCode: String
    public var lines: [ReceiptReviewLine]
    public var subtotalCents: Int?
    public var taxCents: Int?
    public var totalCents: Int?
    public var rawText: String

    /// Builds the review from an extraction, applying remembered corrections:
    /// a line whose text matches a known alias always takes that product's
    /// name, brand and category, whatever Claude said.
    public init(
        extraction: ReceiptExtraction,
        rawText: String,
        hints: [ReceiptHint],
        today: Date,
        defaultCurrency: String
    ) {
        let hintsByKey = Dictionary(hints.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        storeName = extraction.storeName ?? ""
        let parsedDate = ReceiptText.date(fromISO: extraction.purchaseDate)
        // Ignore implausible dates (future, or OCR noise from years ago).
        if let parsedDate, parsedDate <= today.addingTimeInterval(86_400),
           parsedDate > today.addingTimeInterval(-365 * 86_400) {
            purchaseDate = parsedDate
        } else {
            purchaseDate = today
        }
        currencyCode = extraction.currency ?? defaultCurrency
        lines = extraction.items.map { item in
            ReceiptReviewLine(item: item, hint: hintsByKey[ReceiptText.key(item.rawText)])
        }
        subtotalCents = ReceiptText.cents(extraction.subtotal)
        taxCents = ReceiptText.cents(extraction.tax)
        totalCents = ReceiptText.cents(extraction.total)
        self.rawText = rawText
    }

    public var includedLines: [ReceiptReviewLine] { lines.filter(\.include) }

    public var canImport: Bool {
        !includedLines.isEmpty && includedLines.allSatisfy(\.isValid)
    }

    public var totalsCheck: TotalsCheck {
        TotalsCheck(
            itemsCents: lines.compactMap(\.priceCents).reduce(0, +),
            subtotalCents: subtotalCents ?? totalCents.map { $0 - (taxCents ?? 0) }
        )
    }
}

/// Compares the sum of all extracted line prices (included or not) with the
/// printed subtotal, to flag missed or misread lines.
public struct TotalsCheck: Sendable, Equatable {
    public var itemsCents: Int
    public var subtotalCents: Int?

    /// Allowed rounding slack.
    static let toleranceCents = 5

    public var differenceCents: Int? {
        subtotalCents.map { itemsCents - $0 }
    }

    public var isConsistent: Bool {
        guard let differenceCents else { return true }
        return abs(differenceCents) <= Self.toleranceCents
    }
}
