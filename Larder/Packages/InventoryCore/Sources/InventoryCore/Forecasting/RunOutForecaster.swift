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
        /// The inventory item this stock is, for per-item estimates.
        public var id: UUID?
        public var quantity: Double
        public var unit: MeasureUnit
        /// When `quantity` was last known to be accurate (purchase, a logged
        /// use, a count or an edit).
        public var observedAt: Date
        /// When the item was bought. Older items are assumed to be used first.
        public var acquiredAt: Date

        public init(id: UUID? = nil, quantity: Double, unit: MeasureUnit, observedAt: Date, acquiredAt: Date? = nil) {
            self.id = id
            self.quantity = quantity
            self.unit = unit
            self.observedAt = observedAt
            self.acquiredAt = acquiredAt ?? observedAt
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
    /// Projected amount left in each stocked item, oldest first.
    public var items: [ItemEstimate] = []

    public var isOutOfStock: Bool { estimatedRemaining <= 0.0001 }

    /// Days one typical purchase lasts at the current rate.
    public var daysPerPurchase: Double { typicalPurchaseQuantity / dailyRate }

    public func daysUntilRunOut(from now: Date) -> Double {
        runOutDate.timeIntervalSince(now) / 86_400
    }
}

/// How much of one stocked item is probably left, assuming the household
/// finishes older items before starting newer ones.
public struct ItemEstimate: Sendable, Equatable {
    public var id: UUID?
    /// In the item's own unit.
    public var remaining: Double
    public var unit: MeasureUnit
    /// What was recorded for the item (its last known quantity).
    public var recorded: Double
    /// When the item is projected to be finished.
    public var finishDate: Date

    public init(id: UUID?, remaining: Double, unit: MeasureUnit, recorded: Double, finishDate: Date) {
        self.id = id
        self.remaining = remaining
        self.unit = unit
        self.recorded = recorded
        self.finishDate = finishDate
    }

    /// Projected to be used up, though nobody said so.
    public var isProbablyFinished: Bool { remaining <= 0.0001 && recorded > 0.0001 }

    /// Projected to have been used since it was last recorded.
    public var isProjected: Bool { abs(remaining - recorded) > 0.0001 }

    /// `remaining` rounded for display ("about ½ gal left").
    public var roundedRemaining: Double { unit.roundedEstimate(remaining) }
}

extension MeasureUnit {
    /// Rounds an estimated amount to what reads naturally: quarters for
    /// counted units, tenths below 10 otherwise, whole numbers above. Never
    /// rounds something that's left down to zero.
    public func roundedEstimate(_ value: Double) -> Double {
        guard value > 0.0001 else { return 0 }
        let rounded: Double
        if isDiscrete {
            rounded = (value * 4).rounded() / 4
            return max(rounded, 0.25)
        }
        rounded = value < 10 ? (value * 10).rounded() / 10 : value.rounded()
        return max(rounded, value < 10 ? 0.1 : 1)
    }
}

/// Forecasts when a consumable runs out from purchase and usage history.
///
/// Nobody logs every glass of milk, so the rate is learned mostly from what
/// the household buys: in steady state, what you buy is what you use.
///
/// Rate observations (an amount used over a number of days) come from:
/// 1. "Used up" events: the time from buying an item to finishing it. This is
///    the most direct signal and gets triple weight.
/// 2. Repeat purchases: each purchase's quantity over the gap to the next
///    purchase, assuming it was consumed by then.
///
/// Observations are weighted toward recent ones (each step back in time
/// multiplies the weight by `recencyDecay`), outliers beyond 3× the median
/// rate are dropped, and the rate is total weighted amount over total weighted
/// days, so irregular gaps don't skew it the way averaging per-gap rates
/// would. Logged partial use (recipes, "used some") is incomplete by nature,
/// so it only sets a floor on the rate, or stands alone when nothing else is
/// known. Confidence reflects how many observations there are and how much
/// they vary. With no usable history the category's typical rate is used, at
/// low confidence.
///
/// Stock is projected forward item by item, oldest first: each item starts
/// being used when the one before it runs out (or when it was last counted,
/// if later), so three unlogged gallons bought a week apart don't add up to
/// three gallons on hand.
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
        var quantity: Double
        var days: Double
        var date: Date
        var weight: Double

        var rate: Double { quantity / days }
    }

    public static func forecast(_ history: ConsumptionHistory, now: Date) -> RunOutForecast? {
        let unit = history.unit
        let purchases = mergeSameDay(history.purchases.compactMap { purchase -> ConsumptionHistory.Purchase? in
            guard let quantity = purchase.unit.convert(purchase.quantity, to: unit), quantity > 0 else { return nil }
            return ConsumptionHistory.Purchase(date: purchase.date, quantity: quantity, unit: unit)
        }).filter { $0.date <= now }

        let stock = history.stock.compactMap { item -> ConsumptionHistory.Stock? in
            guard let quantity = item.unit.convert(item.quantity, to: unit) else { return nil }
            var converted = item
            converted.quantity = max(0, quantity)
            converted.unit = unit
            return converted
        }

        guard !purchases.isEmpty || !stock.isEmpty else { return nil }

        var observations = usedUpObservations(history.usages, purchases: purchases, unit: unit)
        let hasUsedUp = !observations.isEmpty
        observations += intervalObservations(purchases)
        let partial = partialUseObservation(history.usages, unit: unit)

        let typicalQuantity = typicalPurchaseQuantity(purchases) ?? stock.map(\.quantity).max() ?? 1

        var rate: Double
        let spread: Double
        var confidence: ForecastConfidence
        var basis: RunOutForecast.Basis
        var count: Int
        let trimmed = trimOutliers(weightedByRecency(observations))
        if !trimmed.isEmpty {
            let (ratio, cv) = weightedRateAndCV(trimmed)
            rate = ratio
            spread = min(max(cv, 0.1), 0.8)
            confidence = Self.confidence(count: trimmed.count, cv: cv)
            basis = hasUsedUp ? .usage : .purchaseHistory
            count = trimmed.count
            // Logged use is a lower bound: it can't exceed what was used.
            if let partial, partial.rate > rate {
                rate = partial.rate
                basis = .usage
            }
        } else if let partial {
            rate = partial.rate
            spread = 0.5
            confidence = .low
            basis = .usage
            count = 1
        } else {
            rate = typicalQuantity / defaultDaysPerPurchase(for: history.category)
            spread = 0.5
            confidence = .low
            basis = .categoryDefault
            count = 0
        }
        guard rate > 0, rate.isFinite else { return nil }

        let items = project(stock, rate: rate, now: now, itemUnits: history.stock.map(\.unit))
        let remaining = items.map(\.remainingInForecastUnit).reduce(0, +)

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
            observationCount: count,
            typicalPurchaseQuantity: typicalQuantity,
            items: items.map(\.estimate)
        )
    }

    // MARK: - Stock projection

    struct ProjectedItem {
        var estimate: ItemEstimate
        var remainingInForecastUnit: Double
    }

    /// Walks stocked items oldest first. Each starts being used at the later
    /// of when it was last observed and when the previous item ran out, and
    /// lasts its quantity divided by the rate.
    static func project(
        _ stock: [ConsumptionHistory.Stock],
        rate: Double,
        now: Date,
        itemUnits: [MeasureUnit]
    ) -> [ProjectedItem] {
        let ordered = zip(stock, itemUnits).sorted { lhs, rhs in
            (lhs.0.acquiredAt, lhs.0.observedAt) < (rhs.0.acquiredAt, rhs.0.observedAt)
        }
        var previousFinish = Date.distantPast
        return ordered.map { item, itemUnit in
            let start = max(item.observedAt, previousFinish)
            let finish = start.addingTimeInterval(item.quantity / rate * day)
            previousFinish = finish
            let used = max(0, now.timeIntervalSince(start) / day) * rate
            let left = max(0, item.quantity - used)
            let toItemUnit = { (value: Double) in item.unit.convert(value, to: itemUnit) ?? value }
            return ProjectedItem(
                estimate: ItemEstimate(
                    id: item.id,
                    remaining: toItemUnit(left),
                    unit: itemUnit,
                    recorded: toItemUnit(item.quantity),
                    finishDate: finish
                ),
                remainingInForecastUnit: left
            )
        }
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
            return Observation(quantity: quantity, days: days, date: usage.date, weight: usedUpWeight)
        }
    }

    static func intervalObservations(_ purchases: [ConsumptionHistory.Purchase]) -> [Observation] {
        guard purchases.count >= 2 else { return [] }
        return zip(purchases, purchases.dropFirst()).compactMap { current, next in
            let days = next.date.timeIntervalSince(current.date) / day
            guard days >= 1 else { return nil }
            return Observation(quantity: current.quantity, days: days, date: next.date, weight: 1)
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
        return Observation(quantity: total, days: days, date: last, weight: 1)
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

    /// Rate as weighted total amount over weighted total days, plus the
    /// weighted coefficient of variation of the individual rates.
    static func weightedRateAndCV(_ observations: [Observation]) -> (rate: Double, cv: Double) {
        let weightedDays = observations.map { $0.days * $0.weight }.reduce(0, +)
        guard weightedDays > 0 else { return (0, 1) }
        let rate = observations.map { $0.quantity * $0.weight }.reduce(0, +) / weightedDays
        guard observations.count > 1, rate > 0 else { return (rate, 1) }
        let totalWeight = observations.map(\.weight).reduce(0, +)
        let variance = observations.map { $0.weight * pow($0.rate - rate, 2) }.reduce(0, +) / totalWeight
        return (rate, sqrt(variance) / rate)
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
