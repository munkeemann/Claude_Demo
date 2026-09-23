import Foundation

/// The fields of an inventory item that search, filtering and sorting look at.
public struct InventoryItemSummary: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var productName: String
    public var brand: String?
    public var category: ProductCategory
    public var locationID: UUID?
    public var status: ItemStatus
    public var expiryDate: Date?
    public var createdAt: Date
    public var notes: String

    public init(
        id: UUID,
        productName: String,
        brand: String? = nil,
        category: ProductCategory,
        locationID: UUID? = nil,
        status: ItemStatus = .inStock,
        expiryDate: Date? = nil,
        createdAt: Date = Date(),
        notes: String = ""
    ) {
        self.id = id
        self.productName = productName
        self.brand = brand
        self.category = category
        self.locationID = locationID
        self.status = status
        self.expiryDate = expiryDate
        self.createdAt = createdAt
        self.notes = notes
    }
}

public enum InventorySort: String, CaseIterable, Sendable, Identifiable {
    case name
    case expiry
    case recentlyAdded
    case category

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .name: "Name"
        case .expiry: "Expiry date"
        case .recentlyAdded: "Recently added"
        case .category: "Category"
        }
    }
}

/// Search, filter and sort settings for the inventory list.
public struct InventoryFilter: Sendable, Equatable {
    public var searchText: String
    /// Empty means every location.
    public var locationIDs: Set<UUID>
    /// Empty means every category.
    public var categories: Set<ProductCategory>
    /// Empty means every status.
    public var statuses: Set<ItemStatus>
    public var sort: InventorySort

    public init(
        searchText: String = "",
        locationIDs: Set<UUID> = [],
        categories: Set<ProductCategory> = [],
        statuses: Set<ItemStatus> = [.inStock, .low],
        sort: InventorySort = .name
    ) {
        self.searchText = searchText
        self.locationIDs = locationIDs
        self.categories = categories
        self.statuses = statuses
        self.sort = sort
    }

    /// True when anything other than search text and sort differs from the default.
    public var hasActiveFilters: Bool {
        !locationIDs.isEmpty || !categories.isEmpty || statuses != InventoryFilter().statuses
    }

    public func matches(_ item: InventoryItemSummary) -> Bool {
        if !statuses.isEmpty && !statuses.contains(item.status) { return false }
        if !categories.isEmpty && !categories.contains(item.category) { return false }
        if !locationIDs.isEmpty {
            guard let location = item.locationID, locationIDs.contains(location) else { return false }
        }
        let queryTokens = TextNormalizer.tokens(searchText)
        guard !queryTokens.isEmpty else { return true }
        let haystack = TextNormalizer.tokens(
            [item.productName, item.brand ?? "", item.category.displayName, item.notes].joined(separator: " ")
        )
        // Every query token must prefix some word in the item.
        return queryTokens.allSatisfy { query in
            haystack.contains { $0.hasPrefix(query) }
        }
    }

    /// Filters and sorts `items`, reading each one through `summary`.
    public func apply<Item>(_ items: [Item], summary: (Item) -> InventoryItemSummary) -> [Item] {
        let pairs = items.map { (item: $0, summary: summary($0)) }.filter { matches($0.summary) }
        return pairs.sorted { lhs, rhs in
            Self.areInIncreasingOrder(lhs.summary, rhs.summary, by: sort)
        }.map(\.item)
    }

    public func apply(_ items: [InventoryItemSummary]) -> [InventoryItemSummary] {
        apply(items) { $0 }
    }

    static func areInIncreasingOrder(_ lhs: InventoryItemSummary, _ rhs: InventoryItemSummary, by sort: InventorySort) -> Bool {
        func byName() -> Bool {
            let order = lhs.productName.localizedCaseInsensitiveCompare(rhs.productName)
            return order == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : order == .orderedAscending
        }
        switch sort {
        case .name:
            return byName()
        case .expiry:
            // Items without an expiry date sort last.
            switch (lhs.expiryDate, rhs.expiryDate) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return byName()
            }
        case .recentlyAdded:
            return lhs.createdAt == rhs.createdAt ? byName() : lhs.createdAt > rhs.createdAt
        case .category:
            return lhs.category == rhs.category
                ? byName()
                : lhs.category.displayName < rhs.category.displayName
        }
    }
}
