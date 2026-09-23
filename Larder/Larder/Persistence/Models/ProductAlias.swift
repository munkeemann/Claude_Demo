import Foundation
import InventoryCore
import SwiftData

/// Maps external text to a product: a barcode, a raw receipt line
/// ("GV WHL MLK 1G"), or an order-email title. Values are stored normalized
/// (`TextNormalizer.barcode` / `TextNormalizer.key`) so lookups are exact.
@Model
final class ProductAlias {
    var id: UUID = UUID()
    var kindRaw: String = "barcode"
    var value: String = ""
    var createdAt: Date = Date()
    var lastUsedAt: Date = Date()
    var product: Product?

    init(kind: AliasKind, value: String, now: Date = Date()) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.value = value
        self.createdAt = now
        self.lastUsedAt = now
    }

    var kind: AliasKind {
        get { AliasKind(rawValue: kindRaw) ?? .barcode }
        set { kindRaw = newValue.rawValue }
    }
}
