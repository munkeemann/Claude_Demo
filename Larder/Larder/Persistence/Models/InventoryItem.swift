import Foundation
import InventoryCore
import SwiftData

/// A stocked instance of a product: "the half gallon of milk in the fridge".
@Model
final class InventoryItem {
    var id: UUID = UUID()
    var quantity: Double = 1
    /// How much was stocked originally; "low" is measured against this.
    var initialQuantity: Double = 1
    var unitRaw: String = "each"
    var purchaseDate: Date = Date()
    /// When to use it by: worked out from the fields below by
    /// `InventoryStore.refreshExpiry`, and stored so reminders, filters and
    /// the other phones in the home read one value.
    var expiryDate: Date?
    /// A date set before package dates were tracked separately; kept as is.
    var expiryIsOverride: Bool = false
    /// The date printed on the package.
    var printedExpiryDate: Date?
    var openedDate: Date?
    /// When it moved to its current kind of storage; nil means since purchase.
    var climateSince: Date?
    /// Share of its unopened shelf life used before `climateSince`.
    var shelfLifeUsed: Double = 0
    /// When it came out of the freezer.
    var thawedDate: Date?
    /// Added with "leave expiry blank": no estimate unless a date is entered.
    var expiryTrackingOff: Bool = false
    /// When `quantity` was last known to be accurate (a quick action or a
    /// quantity edit). Forecasts project consumption from here; nil means
    /// the purchase date.
    var quantityObservedAt: Date?
    var statusRaw: String = "inStock"
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var product: Product?
    var location: StorageLocation?

    @Relationship(deleteRule: .nullify, inverse: \UsageEvent.item)
    var usages: [UsageEvent]? = []

    init(
        quantity: Double,
        unit: MeasureUnit,
        purchaseDate: Date,
        expiryDate: Date? = nil,
        expiryIsOverride: Bool = false,
        notes: String = "",
        now: Date = Date()
    ) {
        self.id = UUID()
        self.quantity = quantity
        self.initialQuantity = quantity
        self.unitRaw = unit.rawValue
        self.purchaseDate = purchaseDate
        self.expiryDate = expiryDate
        self.expiryIsOverride = expiryIsOverride
        self.notes = notes
        self.statusRaw = QuickActionCalculator.status(forQuantity: quantity, initialQuantity: quantity).rawValue
        self.createdAt = now
        self.updatedAt = now
    }

    var unit: MeasureUnit {
        get { MeasureUnit(rawValue: unitRaw) ?? .each }
        set { unitRaw = newValue.rawValue }
    }

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .inStock }
        set { statusRaw = newValue.rawValue }
    }

    var displayName: String { product?.displayName ?? "Unknown item" }

    var quantityLabel: String { unit.label(for: quantity) }

    var state: ItemState {
        ItemState(quantity: quantity, initialQuantity: initialQuantity, unit: unit, status: status)
    }

    var summary: InventoryItemSummary {
        InventoryItemSummary(
            id: id,
            productName: product?.name ?? "",
            brand: product?.brand,
            category: product?.category ?? .other,
            locationID: location?.id,
            status: status,
            expiryDate: expiryDate,
            createdAt: createdAt,
            notes: notes
        )
    }

    /// A draft for editing this item.
    var draft: ItemDraft {
        var draft = ItemDraft(
            name: product?.name ?? "",
            brand: product?.brand ?? "",
            category: product?.category ?? .other,
            quantity: quantity,
            unit: unit,
            locationID: location?.id,
            purchaseDate: purchaseDate,
            expiryDate: printedExpiryDate ?? (expiryIsOverride ? expiryDate : nil),
            notes: notes,
            barcode: product?.barcodes.first,
            packageSizeText: product?.packageSizeText,
            imageURL: product?.imageURL
        )
        if let product {
            draft.isIngredient = product.isIngredient
            draft.tracksRunOut = product.tracksRunOut
            draft.tracksExpiry = product.tracksExpiry
        }
        draft.openedDate = openedDate
        return draft
    }

    /// A draft for buying this product again: same product, location and
    /// amount, purchased today, expiry left for estimation.
    func restockDraft(now: Date = Date()) -> ItemDraft {
        var draft = self.draft
        draft.quantity = initialQuantity
        draft.purchaseDate = now
        draft.expiryDate = nil
        draft.openedDate = nil
        draft.notes = ""
        return draft
    }
}
