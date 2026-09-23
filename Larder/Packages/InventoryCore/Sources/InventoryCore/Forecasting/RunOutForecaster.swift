import Foundation

/// A product's purchase and usage history, in plain values.
public struct ConsumptionHistory: Sendable {
    public struct Purchase: Sendable, Equatable {
        public var date: Date
        public var quantity: Double
        public var unit: MeasureUnit

        public init(date: Date, quantity: Double, unit: MeasureUnit) {
            self.date = date
            self.quantity = quantity
            self.unit = unit
        }
    }

    public struct Usage: Sendable, Equatable {
        public var date: Date
        public var quantity: Double
        public var unit: MeasureUnit
        public var type: UsageType
        /// When the item used up was bought, and how much it held, if the
        /// usage is linked to an item. Unlinked "used up" events are paired
        /// with the latest earlier purchase instead.
        public var itemPurchaseDate: Date?
        public var itemInitialQuantity: Double?

        public init(
            date: Date,
            quantity: Double,
            unit: MeasureUnit,
            type: UsageType,
            itemPurchaseDate: Date? = nil,
            itemInitialQuantity: Double? = nil
        ) {
            self.date = date
            self.quantity = quantity
            self.unit = unit
            self.type = type
            self.itemPurchaseDate = itemPurchaseDate
            self.itemInitialQuantity = itemInitialQuantity
        }
    }

    public struct Stock: Sendable, Equatable {
        public var quantity: Double
        public var unit: MeasureUnit
        /// When `quantity` was last known to be accurate (purchase or last
        /// logged usage).
        public var observedAt: Date

        public init(quantity: Double, unit: MeasureUnit, observedAt: Date) {
            self.quantity = quantity
            self.unit = unit
            self.observedAt = observedAt
        }
    }

    public var category: ProductCategory
    /// Unit all quantities are converted to.
    public var unit: MeasureUnit
    public var purchases: [Purchase]
    public var usages: [Usage]
    /// Items currently in stock.
    public var stock: [Stock]

    public init(category: ProductCategory, unit: MeasureUnit, purchases: [Purchase], usages: [Usage], stock: [Stock]) {
        self.category = category
        self.unit = unit
        self.purchases = purchases
        self.usages = usages
        self.stock = stock
    }
}

public enum ForecastConfidence: Int, Sendable, Comparable, CaseIterable {
    case low
    case medium
    case high

    public static func < (lhs: ForecastConfidence, rhs: ForecastConfidence) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .low: "Low confidence"
        case .medium: "Medium confidence"
        case .high: "High confidence"
        }
    }
}

public struct RunOutForecast: Sendable, Equatable {
    public enum Basis: String, Sendable {
        /// Logged usage ("used up" taps, partial-use logs), possibly mixed
        /// with purchase intervals.
        case usage
        /// Only the intervals between repeat purchases.
        case purchaseHistory
        /// Not enough history; a typical rate for the category.
        case categoryDefault
    }

    /// Consumption in `unit` per day.
    public var dailyRate: Double
    public var unit: MeasureUnit
    /// Estimated amount left now, after projecting consumption since the
    /// last observation.
    public var estimatedRemaining: Double
    /// When the household is expected to run out. Equal to `now` when it
    /// probably already has.
    public var runOutDate: Date
    public var earliest: Date
    public var latest: Date
    public var confidence: ForecastConfidence
    public var basis: Basis
    public var observationCount: Int
    /// Most common recent purchase amount, for the shopping list.
    public var typicalPurchaseQuantity: Double

    public var isOutOfStock: Bool { estimatedRemaining <= 0.0001 }

    public func daysUntilRunOut(from now: Date) -> Double {
        runOutDate.timeIntervalSince(now) / 86_400
    }
}

/// Forecasts when a consumable runs out from purchase and usage history.
///
/// Rate observations (units per day) come from three sources:
/// 1. "Used up" events: the time from buying an item to finishing it. This is
///    the most direct signal and gets triple weight.
/// 2. Repeat purchases: each purchase's quantity divided by the gap to the
///    next purchase, assuming it was consumed by then.
/// 3. Logged partial use: total logged amount over the span it covers, as one
///    extra observation when there are at least three such logs.
///
/// Observations are weighted toward recent ones (each step back in time
/// multiplies the weight by `recencyDecay`), outliers beyond 3× the median are
/// dropped, and a weighted mean gives the rate. Confidence reflects how many
/// observations there are and how much they vary. With no usable history the
/// category's typical rate is used, at low confidence.
public enum RunOutForecaster {
    static let recencyDecay = 0.75
    static let usedUpWeight = 3.0
    static let day: TimeInterval = 86_400
    static let minimumSpanDays = 0.5

    /// Typical days one purchase lasts, by category.
    public static func defaultDaysPerPurchase(for category: ProductCategory) -> Double {
        switch category {
        case .leftovers: 3
        case .meat, .seafood, .bakery: 5
        case .dairy, .produce, .deli: 7
        case .snacks: 10
        case .eggs, .beverages, .baby: 14
        case .cheese: 21
        case .frozen, .grains, .canned, .paperGoods, .pet, .other: 30
        case .cleaning, .laundry, .personalCare: 45
        case .condiments, .health: 60
        case .spices: 180
        }
    }

    struct Observation {
        var rate: Double
        var date: Date
        var weight: Double
    }

    public static func forecast(_ history: ConsumptionHistory, now: Date) -> RunOutForecast? {
        let unit = history.unit
        let purchases = mergeSameDay(history.purchases.compactMap { purchase -> ConsumptionHistory.Purchase? in
            guard let quantity = purchase.unit.convert(purchase.quantity, to: unit), quantity > 0 else { return nil }
            return ConsumptionHistory.Purchase(date: purchase.date, quantity: quantity, unit: unit)
        }).filter { $0.date <= now }

        let stock = history.stock.compactMap { item -> ConsumptionHistory.Stock? in
            guard let quantity = item.unit.convert(item.quantity, to: unit) else { return nil }
            return ConsumptionHistory.Stock(quantity: max(0, quantity), unit: unit, observedAt: item.observedAt)
        }

        guard !purchases.isEmpty || !stock.isEmpty else { return nil }

        var observations = usedUpObservations(history.usages, purchases: purchases, unit: unit)
        let usedUpCount = observations.count
        observations += intervalObservations(purchases)
        let partial = partialUseObservation(history.usages, unit: unit)
        if let partial { observations.append(partial) }
        let hasUsageSignal = usedUpCount > 0 || partial != nil

        let typicalQuantity = typicalPurchaseQuantity(purchases) ?? stock.map(\.quantity).max() ?? 1

        let rate: Double
        let spread: Double
        let confidence: ForecastConfidence
        let basis: RunOutForecast.Basis
        let trimmed = trimOutliers(weightedByRecency(observations))
        if trimmed.isEmpty {
            rate = typicalQuantity / defaultDaysPerPurchase(for: history.category)
            spread = 0.5
            confidence = .low
            basis = .categoryDefault
        } else {
            let (mean, cv) = weightedMeanAndCV(trimmed)
            rate = mean
            spread = min(max(cv, 0.1), 0.8)
            confidence = Self.confidence(count: trimmed.count, cv: cv)
            basis = hasUsageSignal ? .usage : .purchaseHistory
        }
        guard rate > 0, rate.isFinite else { return nil }

        // Project consumption since the stock was last observed.
        let recorded = stock.map(\.quantity).reduce(0, +)
        let lastObserved = stock.map(\.observedAt).max() ?? now
        let elapsedDays = max(0, now.timeIntervalSince(lastObserved) / day)
        let remaining = max(0, recorded - rate * elapsedDays)

        let daysLeft = remaining / rate
        let fastRate = rate * (1 + spread)
        let slowRate = rate * (1 - spread)
        return RunOutForecast(
            dailyRate: rate,
            unit: unit,
            estimatedRemaining: remaining,
            runOutDate: now.addingTimeInterval(daysLeft * day),
            earliest: now.addingTimeInterval(remaining / fastRate * day),
            latest: now.addingTimeInterval(remaining / slowRate * day),
            confidence: confidence,
            basis: basis,
            observationCount: trimmed.count,
            typicalPurchaseQuantity: typicalQuantity
        )
    }

    // MARK: - Observations

    static func usedUpObservations(
        _ usages: [ConsumptionHistory.Usage],
        purchases: [ConsumptionHistory.Purchase],
        unit: MeasureUnit
    ) -> [Observation] {
        usages.filter { $0.type == .usedUp }.compactMap { usage in
            let start: Date
            let quantity: Double
            if let purchaseDate = usage.itemPurchaseDate,
               let initial = usage.itemInitialQuantity.flatMap({ usage.unit.convert($0, to: unit) }) {
                start = purchaseDate
                quantity = initial
            } else if let purchase = purchases.last(where: { $0.date < usage.date }) {
                start = purchase.date
                quantity = purchase.quantity
            } else {
                return nil
            }
            let days = max(minimumSpanDays, usage.date.timeIntervalSince(start) / day)
            guard quantity > 0 else { return nil }
            return Observation(rate: quantity / days, date: usage.date, weight: usedUpWeight)
        }
    }

    static func intervalObservations(_ purchases: [ConsumptionHistory.Purchase]) -> [Observation] {
        guard purchases.count >= 2 else { return [] }
        return zip(purchases, purchases.dropFirst()).compactMap { current, next in
            let days = next.date.timeIntervalSince(current.date) / day
            guard days >= 1 else { return nil }
            return Observation(rate: current.quantity / days, date: next.date, weight: 1)
        }
    }

    static func partialUseObservation(_ usages: [ConsumptionHistory.Usage], unit: MeasureUnit) -> Observation? {
        let logged = usages
            .filter { $0.type != .discarded }
            .compactMap { usage -> (Date, Double)? in
                usage.unit.convert(usage.quantity, to: unit).map { (usage.date, $0) }
            }
            .sorted { $0.0 < $1.0 }
        guard logged.count >= 3, let first = logged.first?.0, let last = logged.last?.0 else { return nil }
        let days = last.timeIntervalSince(first) / day
        guard days >= 1 else { return nil }
        // The first log's amount was used before the span starts.
        let total = logged.dropFirst().map(\.1).reduce(0, +)
        guard total > 0 else { return nil }
        return Observation(rate: total / days, date: last, weight: 1)
    }

    // MARK: - Statistics

    /// Most recent observations weigh most.
    static func weightedByRecency(_ observations: [Observation]) -> [Observation] {
        observations
            .sorted { $0.date > $1.date }
            .enumerated()
            .map { index, observation in
                var weighted = observation
                weighted.weight *= pow(recencyDecay, Double(index))
                return weighted
            }
    }

    static func trimOutliers(_ observations: [Observation]) -> [Observation] {
        guard observations.count >= 3 else { return observations }
        let rates = observations.map(\.rate).sorted()
        let median = rates.count.isMultiple(of: 2)
            ? (rates[rates.count / 2 - 1] + rates[rates.count / 2]) / 2
            : rates[rates.count / 2]
        return observations.filter { $0.rate <= median * 3 && $0.rate >= median / 3 }
    }

    static func weightedMeanAndCV(_ observations: [Observation]) -> (mean: Double, cv: Double) {
        let totalWeight = observations.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return (0, 1) }
        let mean = observations.map { $0.rate * $0.weight }.reduce(0, +) / totalWeight
        guard observations.count > 1, mean > 0 else { return (mean, 1) }
        let variance = observations.map { $0.weight * pow($0.rate - mean, 2) }.reduce(0, +) / totalWeight
        return (mean, sqrt(variance) / mean)
    }

    static func confidence(count: Int, cv: Double) -> ForecastConfidence {
        if count >= 4 && cv <= 0.35 { return .high }
        if count >= 2 && cv <= 0.6 { return .medium }
        return .low
    }

    // MARK: - Helpers

    /// Purchases less than 12 hours apart are one shopping trip.
    public static func mergeSameDay(_ purchases: [ConsumptionHistory.Purchase]) -> [ConsumptionHistory.Purchase] {
        var merged: [ConsumptionHistory.Purchase] = []
        for purchase in purchases.sorted(by: { $0.date < $1.date }) {
            if let last = merged.last, purchase.date.timeIntervalSince(last.date) < 12 * 3600 {
                merged[merged.count - 1].quantity += purchase.quantity
            } else {
                merged.append(purchase)
            }
        }
        return merged
    }

    /// The most common of the last five purchase amounts (ties go to the most
    /// recent), so one bulk buy doesn't change the usual order.
    static func typicalPurchaseQuantity(_ purchases: [ConsumptionHistory.Purchase]) -> Double? {
        let recent = purchases.suffix(5).map(\.quantity)
        guard !recent.isEmpty else { return nil }
        var counts: [Double: Int] = [:]
        for quantity in recent { counts[quantity, default: 0] += 1 }
        let best = counts.values.max() ?? 0
        return recent.reversed().first { counts[$0] == best }
    }
}
