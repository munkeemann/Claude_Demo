import Foundation

/// What a household threw out, month by month, and roughly what it cost.
public struct WasteReport: Sendable, Equatable {
    public struct Usage: Sendable, Equatable {
        public var productID: UUID
        public var name: String
        public var category: ProductCategory
        public var date: Date
        public var quantity: Double
        public var unit: MeasureUnit
        public var type: UsageType

        public init(productID: UUID, name: String, category: ProductCategory, date: Date, quantity: Double, unit: MeasureUnit, type: UsageType) {
            self.productID = productID
            self.name = name
            self.category = category
            self.date = date
            self.quantity = quantity
            self.unit = unit
            self.type = type
        }
    }

    public struct Purchase: Sendable, Equatable {
        public var productID: UUID
        public var date: Date
        public var quantity: Double
        public var unit: MeasureUnit
        public var priceCents: Int

        public init(productID: UUID, date: Date, quantity: Double, unit: MeasureUnit, priceCents: Int) {
            self.productID = productID
            self.date = date
            self.quantity = quantity
            self.unit = unit
            self.priceCents = priceCents
        }
    }

    public struct Tossed: Sendable, Equatable, Identifiable {
        public var id: String { "\(productID)-\(date.timeIntervalSinceReferenceDate)" }
        public var productID: UUID
        public var name: String
        public var category: ProductCategory
        public var date: Date
        public var quantity: Double
        public var unit: MeasureUnit
        /// nil when no purchase price is known.
        public var costCents: Int?
    }

    public struct Month: Sendable, Equatable, Identifiable {
        public var id: Date { start }
        public var start: Date
        public var tossed: [Tossed]
        /// Items finished rather than thrown out.
        public var usedUpCount: Int

        public var tossedCount: Int { tossed.count }
        /// Estimated cost of what was thrown out (known prices only).
        public var tossedCents: Int { tossed.compactMap(\.costCents).reduce(0, +) }
        /// Some tossed items have no price, so the cost is a floor.
        public var hasUnpricedItems: Bool { tossed.contains { $0.costCents == nil } }

        /// Share of finished items that were thrown out rather than used.
        public var wasteShare: Double? {
            let total = tossedCount + usedUpCount
            return total == 0 ? nil : Double(tossedCount) / Double(total)
        }

        /// Categories by how many items were thrown out, most first.
        public var topCategories: [(category: ProductCategory, count: Int)] {
            Dictionary(grouping: tossed, by: \.category)
                .map { (category: $0.key, count: $0.value.count) }
                .sorted { ($0.count, $1.category.rawValue) > ($1.count, $0.category.rawValue) }
        }
    }

    /// Newest month first.
    public var months: [Month]

    public var thisMonth: Month? { months.first }

    /// Builds the last `monthCount` calendar months, ending with the one
    /// containing `now`.
    public static func build(
        usages: [Usage],
        purchases: [Purchase],
        monthCount: Int = 6,
        now: Date,
        calendar: Calendar = .current
    ) -> WasteReport {
        guard monthCount > 0, let current = calendar.dateInterval(of: .month, for: now)?.start else {
            return WasteReport(months: [])
        }
        let starts = (0..<monthCount).compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
        let pricesByProduct = Dictionary(grouping: purchases, by: \.productID)
            .mapValues { $0.sorted { $0.date < $1.date } }

        var months = starts.map { Month(start: $0, tossed: [], usedUpCount: 0) }
        for usage in usages {
            guard let start = calendar.dateInterval(of: .month, for: usage.date)?.start,
                  let index = months.firstIndex(where: { $0.start == start })
            else { continue }
            switch usage.type {
            case .discarded:
                months[index].tossed.append(Tossed(
                    productID: usage.productID,
                    name: usage.name,
                    category: usage.category,
                    date: usage.date,
                    quantity: usage.quantity,
                    unit: usage.unit,
                    costCents: cost(of: usage, prices: pricesByProduct[usage.productID] ?? [])
                ))
            case .usedUp:
                months[index].usedUpCount += 1
            case .partiallyUsed:
                break
            }
        }
        for index in months.indices {
            months[index].tossed.sort { $0.date > $1.date }
        }
        return WasteReport(months: months)
    }

    /// The tossed amount at the unit price of the latest priced purchase
    /// before it (or the earliest one, if it was bought later).
    static func cost(of usage: Usage, prices: [Purchase]) -> Int? {
        guard usage.quantity > 0 else { return nil }
        let purchase = prices.last { $0.date <= usage.date } ?? prices.first
        guard let purchase, purchase.quantity > 0, purchase.priceCents > 0 else { return nil }
        let amount: Double
        if let converted = usage.unit.convert(usage.quantity, to: purchase.unit) {
            amount = converted
        } else if usage.unit.isDiscrete && purchase.unit.isDiscrete {
            amount = usage.quantity
        } else {
            return nil
        }
        let cents = Double(purchase.priceCents) / purchase.quantity * amount
        return Int(min(cents, Double(purchase.priceCents) * 10).rounded())
    }
}
