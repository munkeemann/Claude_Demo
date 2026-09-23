import Foundation

/// A product's forecast plus what the shopping list needs to know about it.
public struct ProductForecast: Sendable, Identifiable {
    public var id: UUID { productID }
    public var productID: UUID
    public var name: String
    public var category: ProductCategory
    public var forecast: RunOutForecast
    /// Number of separate purchases on record.
    public var purchaseCount: Int
    public var lastPurchaseDate: Date?
    /// True when an in-stock item is already marked low.
    public var isMarkedLow: Bool

    public init(
        productID: UUID,
        name: String,
        category: ProductCategory,
        forecast: RunOutForecast,
        purchaseCount: Int,
        lastPurchaseDate: Date?,
        isMarkedLow: Bool
    ) {
        self.productID = productID
        self.name = name
        self.category = category
        self.forecast = forecast
        self.purchaseCount = purchaseCount
        self.lastPurchaseDate = lastPurchaseDate
        self.isMarkedLow = isMarkedLow
    }
}

public struct ShoppingSuggestion: Sendable, Equatable, Identifiable {
    public enum Reason: Sendable, Equatable {
        case runningOut(Date)
        case outOfStock
    }

    public var id: UUID { productID }
    public var productID: UUID
    public var name: String
    public var quantity: Double
    public var unit: MeasureUnit
    public var reason: Reason
    public var confidence: ForecastConfidence
}

public enum ShoppingListGenerator {
    /// Products regularly bought but not purchased in this long are treated
    /// as discontinued rather than "out of stock".
    static let staleAfterDays = 120.0

    /// Products predicted to run out within `horizonDays`, plus regular
    /// purchases that are already out. Low-confidence predictions are only
    /// included when the item is also marked low.
    public static func suggestions(
        from forecasts: [ProductForecast],
        now: Date,
        horizonDays: Double = 7,
        minimumConfidence: ForecastConfidence = .medium,
        excluding existing: Set<UUID> = []
    ) -> [ShoppingSuggestion] {
        let horizon = now.addingTimeInterval(horizonDays * 86_400)
        return forecasts.compactMap { entry -> ShoppingSuggestion? in
            guard !existing.contains(entry.productID) else { return nil }
            let forecast = entry.forecast
            let reason: ShoppingSuggestion.Reason

            if forecast.isOutOfStock {
                let isRegular = entry.purchaseCount >= 2
                let isRecent = entry.lastPurchaseDate.map { now.timeIntervalSince($0) / 86_400 <= staleAfterDays } ?? false
                guard isRegular && isRecent || entry.isMarkedLow else { return nil }
                reason = .outOfStock
            } else {
                guard forecast.runOutDate <= horizon else { return nil }
                guard forecast.confidence >= minimumConfidence || entry.isMarkedLow else { return nil }
                reason = .runningOut(forecast.runOutDate)
            }

            let quantity = forecast.typicalPurchaseQuantity > 0 ? forecast.typicalPurchaseQuantity : 1
            return ShoppingSuggestion(
                productID: entry.productID,
                name: entry.name,
                quantity: quantity,
                unit: forecast.unit,
                reason: reason,
                confidence: forecast.confidence
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.reason, rhs.reason) {
            case (.outOfStock, .runningOut): return true
            case (.runningOut, .outOfStock): return false
            case let (.runningOut(l), .runningOut(r)) where l != r: return l < r
            default: return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }
}
