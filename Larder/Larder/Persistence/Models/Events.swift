import Foundation
import InventoryCore
import SwiftData

/// Append-only purchase log. Forecasting reads the intervals between purchases.
@Model
final class PurchaseEvent {
    var id: UUID = UUID()
    var date: Date = Date()
    var quantity: Double = 1
    var unitRaw: String = "each"
    /// Price in minor units (cents) to avoid floating-point money.
    var priceCents: Int?
    var currencyCode: String = "USD"
    var sourceRaw: String = "manual"
    var storeName: String?
    /// Order number from an order email, used to avoid importing twice.
    var externalOrderID: String?
    var createdAt: Date = Date()

    var product: Product?
    var receipt: Receipt?

    init(
        date: Date,
        quantity: Double,
        unit: MeasureUnit,
        source: PurchaseSource,
        priceCents: Int? = nil,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD",
        storeName: String? = nil,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.date = date
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.sourceRaw = source.rawValue
        self.priceCents = priceCents
        self.currencyCode = currencyCode
        self.storeName = storeName
        self.createdAt = now
    }

    var unit: MeasureUnit {
        get { MeasureUnit(rawValue: unitRaw) ?? .each }
        set { unitRaw = newValue.rawValue }
    }

    var source: PurchaseSource {
        get { PurchaseSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}

/// Append-only usage log written by every quick action. "Used up" taps are
/// the strongest run-out signal.
@Model
final class UsageEvent {
    var id: UUID = UUID()
    var date: Date = Date()
    var quantity: Double = 0
    var unitRaw: String = "each"
    var typeRaw: String = "partiallyUsed"
    var createdAt: Date = Date()

    var product: Product?
    var item: InventoryItem?

    init(date: Date, quantity: Double, unit: MeasureUnit, type: UsageType, now: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.typeRaw = type.rawValue
        self.createdAt = now
    }

    var unit: MeasureUnit {
        get { MeasureUnit(rawValue: unitRaw) ?? .each }
        set { unitRaw = newValue.rawValue }
    }

    var type: UsageType {
        get { UsageType(rawValue: typeRaw) ?? .partiallyUsed }
        set { typeRaw = newValue.rawValue }
    }
}
