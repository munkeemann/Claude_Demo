import Foundation
import InventoryCore
import Observation

/// Owns the app's service implementations. Views read it from the SwiftUI
/// environment; previews and tests inject stubs.
@Observable
@MainActor
final class AppEnvironment {
    let productLookup: any ProductLookupService

    init(productLookup: any ProductLookupService) {
        self.productLookup = productLookup
    }

    static func live() -> AppEnvironment {
        AppEnvironment(productLookup: OpenFactsClient(userAgent: userAgent))
    }

    static func preview() -> AppEnvironment {
        AppEnvironment(productLookup: PreviewProductLookup())
    }

    /// Open Food Facts asks clients to identify themselves.
    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "Larder-iOS/\(version) (personal household inventory app)"
    }
}

/// Offline lookup used by previews: knows a single barcode.
struct PreviewProductLookup: ProductLookupService {
    func lookup(barcode: String) async throws -> ProductLookupResult? {
        guard TextNormalizer.barcode(barcode) == "0076808280593" else { return nil }
        return ProductLookupResult(
            barcode: "0076808280593",
            name: "Spaghetti",
            brand: "Barilla",
            category: .grains,
            packageSize: PackageSize(count: 1, unitSize: Quantity(16, .ounce)),
            packageSizeText: "16 oz",
            source: .food
        )
    }
}
