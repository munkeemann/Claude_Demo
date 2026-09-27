import Foundation

/// Which Open*Facts database a lookup came from.
public enum OpenFactsDatabase: String, CaseIterable, Sendable {
    case food
    case beauty
    case products

    public var host: String {
        switch self {
        case .food: "world.openfoodfacts.org"
        case .beauty: "world.openbeautyfacts.org"
        case .products: "world.openproductsfacts.org"
        }
    }

    public var displayName: String {
        switch self {
        case .food: "Open Food Facts"
        case .beauty: "Open Beauty Facts"
        case .products: "Open Products Facts"
        }
    }
}

/// Product details found for a barcode.
public struct ProductLookupResult: Sendable, Equatable {
    public var barcode: String
    public var name: String
    public var brand: String?
    public var category: ProductCategory
    public var packageSize: PackageSize?
    public var packageSizeText: String?
    public var imageURL: URL?
    public var source: OpenFactsDatabase

    public init(
        barcode: String,
        name: String,
        brand: String? = nil,
        category: ProductCategory,
        packageSize: PackageSize? = nil,
        packageSizeText: String? = nil,
        imageURL: URL? = nil,
        source: OpenFactsDatabase
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.category = category
        self.packageSize = packageSize
        self.packageSizeText = packageSizeText
        self.imageURL = imageURL
        self.source = source
    }
}

public protocol ProductLookupService: Sendable {
    /// Returns nil when no database knows the barcode.
    func lookup(barcode: String) async throws -> ProductLookupResult?
}

public enum ProductLookupError: Error, Equatable {
    case invalidBarcode
    case httpStatus(Int)
    case rateLimited
}
