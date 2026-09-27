import Foundation
import InventoryCore
import SwiftData

extension InventoryStore {
    /// In-stock items, soonest-expiring first.
    func activeItems() throws -> [InventoryItem] {
        try context.fetch(FetchDescriptor<InventoryItem>())
            .filter(\.status.isActive)
            .sorted { ($0.expiryDate ?? .distantFuture, $0.displayName) < ($1.expiryDate ?? .distantFuture, $1.displayName) }
    }

    // MARK: - Scanning things out

    /// Every in-stock item with a short reference and where it's kept, for
    /// matching photos of things being thrown out or used up.
    func scanOutHints() throws -> [ShelfScanHint] {
        try activeItems().enumerated().map { index, item in
            ShelfScanHint(
                ref: "i\(index + 1)",
                itemID: item.id,
                name: item.displayName,
                brand: item.product?.brand,
                quantity: item.quantity,
                initialQuantity: item.initialQuantity,
                unit: item.unit,
                locationName: item.location?.name
            )
        }
    }

    /// Tosses or uses up every included line's item. Returns how many changed.
    @discardableResult
    func applyScanOut(_ review: ScanOutReview) throws -> Int {
        var count = 0
        for line in review.includedLines {
            guard let id = line.matchedItemID, let item = try self.item(id: id), item.status.isActive else { continue }
            try apply(line.action, to: item)
            count += 1
        }
        return count
    }

    // MARK: - Quick Add

    /// Where a new item goes: its category's usual place, unless it's kept
    /// somewhere colder or warmer than that (potatoes in the pantry).
    func location(for category: ProductCategory, storage: StorageClimate?) throws -> StorageLocation? {
        let preferred = try defaultLocation(for: category)
        guard let storage, preferred?.climate != storage else { return preferred }
        let all = try locations()
        return all.first { $0.isBuiltIn && $0.climate == storage } ?? all.first { $0.climate == storage } ?? preferred
    }

    /// Review lines for typed or dictated items, each placed where it's kept.
    func quickAddLines(_ items: [QuickAddItem]) throws -> [ShelfScanLine] {
        try items.map { item in
            item.line(locationID: try location(for: item.category, storage: item.storage)?.id)
        }
    }

    // MARK: - Waste

    /// What was thrown out over the last `months` months, priced from receipts.
    func wasteReport(months: Int = 6) throws -> WasteReport {
        let usages = try context.fetch(FetchDescriptor<UsageEvent>()).compactMap { event -> WasteReport.Usage? in
            guard let product = event.product else { return nil }
            return WasteReport.Usage(
                productID: product.id,
                name: product.displayName,
                category: product.category,
                date: event.date,
                quantity: event.quantity,
                unit: event.unit,
                type: event.type
            )
        }
        let purchases = try context.fetch(FetchDescriptor<PurchaseEvent>()).compactMap { event -> WasteReport.Purchase? in
            guard let product = event.product, let price = event.priceCents else { return nil }
            return WasteReport.Purchase(productID: product.id, date: event.date, quantity: event.quantity, unit: event.unit, priceCents: price)
        }
        return WasteReport.build(usages: usages, purchases: purchases, monthCount: months, now: now())
    }
}
