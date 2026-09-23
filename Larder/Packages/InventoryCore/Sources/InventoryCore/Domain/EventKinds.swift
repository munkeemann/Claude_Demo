/// Lifecycle status of a single inventory item.
public enum ItemStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case inStock
    case low
    case usedUp
    case discarded

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inStock: "In stock"
        case .low: "Low"
        case .usedUp: "Used up"
        case .discarded: "Tossed"
        }
    }

    /// Items that are still physically in the house.
    public var isActive: Bool { self == .inStock || self == .low }
}

/// Where a purchase record came from.
public enum PurchaseSource: String, CaseIterable, Codable, Sendable {
    case receipt
    case barcode
    case email
    case manual
}

/// What happened when an item was consumed.
public enum UsageType: String, CaseIterable, Codable, Sendable {
    case usedUp
    case partiallyUsed
    case discarded
}

/// The kind of external text a `ProductAlias` maps to a product.
public enum AliasKind: String, CaseIterable, Codable, Sendable {
    case barcode
    case receiptText
    case emailText
}
