import Foundation
import InventoryCore
import SwiftData

extension Product {
    /// This product's history as plain values for `RunOutForecaster`.
    var consumptionHistory: ConsumptionHistory {
        let items = self.items ?? []
        let stock = items.filter { $0.status.isActive }.map { item in
            ConsumptionHistory.Stock(
                id: item.id,
                quantity: item.quantity,
                unit: item.unit,
                observedAt: item.quantityObservedAt ?? item.purchaseDate,
                acquiredAt: item.purchaseDate
            )
        }
        let purchases = (self.purchases ?? []).map {
            ConsumptionHistory.Purchase(date: $0.date, quantity: $0.quantity, unit: $0.unit)
        }
        let usages = (self.usages ?? []).map { usage in
            ConsumptionHistory.Usage(
                date: usage.date,
                quantity: usage.quantity,
                unit: usage.unit,
                type: usage.type,
                itemPurchaseDate: usage.item?.purchaseDate,
                itemInitialQuantity: usage.item?.initialQuantity
            )
        }
        return ConsumptionHistory(
            category: category,
            unit: defaultUnit,
            purchases: purchases,
            usages: usages,
            stock: stock
        )
    }
}

/// Runs the forecasting engines over the store's data.
@MainActor
struct ForecastService {
    let context: ModelContext
    var now: () -> Date = Date.init

    init(context: ModelContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    /// Run-out forecasts for every product that tracks run-out and has any
    /// history, soonest first.
    func productForecasts() throws -> [ProductForecast] {
        let today = now()
        return try context.fetch(FetchDescriptor<Product>())
            .filter(\.tracksRunOut)
            .compactMap { product -> ProductForecast? in
                guard let forecast = RunOutForecaster.forecast(product.consumptionHistory, now: today) else { return nil }
                let purchases = product.purchases ?? []
                return ProductForecast(
                    productID: product.id,
                    name: product.displayName,
                    category: product.category,
                    forecast: forecast,
                    purchaseCount: RunOutForecaster.mergeSameDay(purchases.map {
                        ConsumptionHistory.Purchase(date: $0.date, quantity: $0.quantity, unit: $0.unit)
                    }).count,
                    lastPurchaseDate: purchases.map(\.date).max(),
                    isMarkedLow: (product.items ?? []).contains { $0.status == .low }
                )
            }
            .sorted { $0.forecast.runOutDate < $1.forecast.runOutDate }
    }

    /// Every forecast plus per-item estimates, computed once for a screen.
    func snapshot() throws -> ForecastSnapshot {
        ForecastSnapshot(forecasts: try productForecasts())
    }

    /// In-stock items projected to be finished that nobody marked as used up,
    /// oldest first.
    func probablyFinishedItems() throws -> [InventoryItem] {
        let estimates = try snapshot().estimates
        return try context.fetch(FetchDescriptor<InventoryItem>(sortBy: [SortDescriptor(\.purchaseDate)]))
            .filter { $0.status.isActive && estimates[$0.id]?.isProbablyFinished == true }
    }

    /// In-stock items expiring within `days` (including already expired).
    func expiringItems(withinDays days: Int) throws -> [InventoryItem] {
        let today = now()
        let cutoff = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: today)) ?? today
        return try context.fetch(FetchDescriptor<InventoryItem>())
            .filter { item in
                guard item.status.isActive, let expiry = item.expiryDate else { return false }
                return expiry < cutoff
            }
            .sorted { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }
    }

    /// In-stock items past their date, for the app icon badge.
    func expiredItemCount() throws -> Int {
        let today = now()
        return try context.fetch(FetchDescriptor<InventoryItem>())
            .filter { item in
                guard item.status.isActive, let expiry = item.expiryDate else { return false }
                return ExpiryStatus(expiry: expiry, now: today).urgency == .expired
            }
            .count
    }

    /// Suggestions not already on the unchecked shopping list.
    func shoppingSuggestions(horizonDays: Double) throws -> [ShoppingSuggestion] {
        let onList = Set(
            try context.fetch(FetchDescriptor<ShoppingListItem>())
                .filter { !$0.isChecked }
                .compactMap { $0.product?.id }
        )
        return ShoppingListGenerator.suggestions(
            from: try productForecasts(),
            now: now(),
            horizonDays: horizonDays,
            excluding: onList
        )
    }

    /// Everything the notification planner should know about.
    func upcomingEvents() throws -> [UpcomingEvent] {
        let horizon = now().addingTimeInterval(90 * 86_400)
        let expiring = try context.fetch(FetchDescriptor<InventoryItem>())
            .filter { $0.status.isActive && ($0.product?.tracksExpiry ?? false) }
            .compactMap { item -> UpcomingEvent? in
                guard let expiry = item.expiryDate, expiry < horizon else { return nil }
                return UpcomingEvent(name: item.displayName, date: expiry, kind: .expires, itemID: item.id)
            }
        let runningOut = try productForecasts()
            .filter { !$0.forecast.isOutOfStock && $0.forecast.runOutDate < horizon }
            .map { UpcomingEvent(name: $0.name, date: $0.forecast.runOutDate, kind: .runsOut, confidence: $0.forecast.confidence) }
        return expiring + runningOut
    }
}

/// Forecasts for every product, indexed for list rows.
struct ForecastSnapshot {
    var forecasts: [ProductForecast] = []
    var byProduct: [UUID: ProductForecast] = [:]
    /// Projected amount left in each stocked item, by item ID.
    var estimates: [UUID: ItemEstimate] = [:]

    init(forecasts: [ProductForecast] = []) {
        self.forecasts = forecasts
        for entry in forecasts {
            byProduct[entry.productID] = entry
            for estimate in entry.forecast.items {
                if let id = estimate.id { estimates[id] = estimate }
            }
        }
    }

    static let empty = ForecastSnapshot()
}
