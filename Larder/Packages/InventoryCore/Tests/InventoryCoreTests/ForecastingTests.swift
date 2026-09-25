import Foundation
import Testing
@testable import InventoryCore

/// Shared helpers: dates are expressed as "days ago" relative to a fixed now.
enum ForecastFixtures {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    static func purchases(_ days: [Double], quantity: Double = 1, unit: MeasureUnit = .each) -> [ConsumptionHistory.Purchase] {
        days.map { ConsumptionHistory.Purchase(date: daysAgo($0), quantity: quantity, unit: unit) }
    }

    static func usedUp(_ days: [Double], unit: MeasureUnit = .each) -> [ConsumptionHistory.Usage] {
        days.map { ConsumptionHistory.Usage(date: daysAgo($0), quantity: 1, unit: unit, type: .usedUp) }
    }

    static func stock(_ quantity: Double, unit: MeasureUnit = .each, observedDaysAgo: Double = 0) -> [ConsumptionHistory.Stock] {
        [ConsumptionHistory.Stock(quantity: quantity, unit: unit, observedAt: daysAgo(observedDaysAgo))]
    }
}

struct ShelfLifeTests {
    let purchase = ForecastFixtures.now

    @Test func tableCoversEveryFoodCategoryAndNoHouseholdOnes() {
        for category in ProductCategory.allCases {
            for climate in StorageClimate.allCases {
                let days = ShelfLifeTable.days(for: category, climate: climate)
                if category.isFood {
                    #expect((days ?? 0) > 0, "\(category) \(climate)")
                } else {
                    #expect(days == nil, "\(category) \(climate)")
                }
            }
        }
    }

    @Test func colderIsNeverShorterForPerishables() {
        for category in ProductCategory.allCases where category.defaultTracksExpiry && category != .frozen {
            let room = ShelfLifeTable.days(for: category, climate: .room)!
            let fridge = ShelfLifeTable.days(for: category, climate: .fridge)!
            let freezer = ShelfLifeTable.days(for: category, climate: .freezer)!
            #expect(room <= fridge && fridge <= freezer, "\(category)")
        }
    }

    @Test func estimatesFromCategoryAndClimate() throws {
        let milk = try #require(ExpiryEstimator.estimate(purchaseDate: purchase, category: .dairy, climate: .fridge))
        #expect(milk.shelfLifeDays == 7)
        #expect(milk.source == .categoryDefault)
        #expect(milk.date == Calendar.current.date(byAdding: .day, value: 7, to: purchase))

        let frozenMilk = try #require(ExpiryEstimator.estimate(purchaseDate: purchase, category: .dairy, climate: .freezer))
        #expect(frozenMilk.shelfLifeDays == 90)
    }

    @Test func productOverrideWins() throws {
        let spinach = try #require(ExpiryEstimator.estimate(
            purchaseDate: purchase, category: .produce, climate: .fridge, productShelfLifeDays: 5
        ))
        #expect(spinach.shelfLifeDays == 5)
        #expect(spinach.source == .product)
    }

    @Test func householdGoodsHaveNoExpiry() {
        #expect(ExpiryEstimator.estimate(purchaseDate: purchase, category: .cleaning, climate: .room) == nil)
    }
}

struct RunOutForecasterTests {
    typealias F = ForecastFixtures

    func forecast(
        purchases: [ConsumptionHistory.Purchase],
        usages: [ConsumptionHistory.Usage] = [],
        stock: [ConsumptionHistory.Stock],
        category: ProductCategory = .dairy,
        unit: MeasureUnit = .each
    ) throws -> RunOutForecast {
        let history = ConsumptionHistory(category: category, unit: unit, purchases: purchases, usages: usages, stock: stock)
        return try #require(RunOutForecaster.forecast(history, now: F.now))
    }

    @Test func steadyWeeklyBuyerIsHighConfidence() throws {
        let result = try forecast(
            purchases: F.purchases([42, 35, 28, 21, 14, 7, 0]),
            stock: F.stock(1)
        )
        #expect(abs(result.dailyRate - 1.0 / 7) < 0.001)
        #expect(result.confidence == .high)
        #expect(result.basis == .purchaseHistory)
        #expect(abs(result.daysUntilRunOut(from: F.now) - 7) < 0.01)
        #expect(result.earliest < result.runOutDate && result.runOutDate < result.latest)
    }

    @Test func usedUpTapsDominatePurchaseIntervals() throws {
        // Bought weekly, but always finished within 4 days of buying.
        let result = try forecast(
            purchases: F.purchases([28, 21, 14, 7]),
            usages: F.usedUp([24, 17, 10, 3]),
            stock: []
        )
        #expect(result.basis == .usage)
        // Used-up rate is 1/4, intervals 1/7; triple weight pulls toward 1/4.
        #expect(result.dailyRate > 0.2)
        #expect(result.isOutOfStock)
        #expect(result.runOutDate == F.now)
    }

    @Test func linkedUsageUsesTheItemsOwnPurchaseDate() throws {
        let usage = ConsumptionHistory.Usage(
            date: F.daysAgo(2), quantity: 0.5, unit: .gallon, type: .usedUp,
            itemPurchaseDate: F.daysAgo(12), itemInitialQuantity: 1
        )
        let result = try forecast(
            purchases: F.purchases([12, 2], unit: .gallon),
            usages: [usage],
            stock: F.stock(1, unit: .gallon),
            unit: .gallon
        )
        // Only observations: used-up 1 gal over 10 days, interval 1 gal over 10 days.
        #expect(abs(result.dailyRate - 0.1) < 0.0001)
    }

    @Test func weightsRecentIntervalsMore() throws {
        // Used to buy monthly; lately weekly.
        let result = try forecast(
            purchases: F.purchases([120, 90, 60, 30, 23, 16, 9, 2]),
            stock: F.stock(1)
        )
        let monthlyRate: Double = 1.0 / 30
        let weeklyRate: Double = 1.0 / 7
        let unweightedMean: Double = (3 * monthlyRate + 4 * weeklyRate) / 7
        #expect(result.dailyRate > unweightedMean)
    }

    @Test func dropsOutliers() throws {
        // A one-off 2-day gap (party week) among ~10-day gaps.
        let result = try forecast(
            purchases: F.purchases([52, 42, 32, 30, 20, 10]),
            stock: F.stock(1)
        )
        #expect(result.observationCount == 4)
        #expect(abs(result.dailyRate - 0.1) < 0.001)
        #expect(result.confidence == .high)
    }

    @Test func irregularHistoryIsLowerConfidence() throws {
        let result = try forecast(
            purchases: F.purchases([60, 50, 30, 25, 5]),
            stock: F.stock(1)
        )
        #expect(result.confidence < .high)
    }

    @Test func bulkBuyScalesByQuantity() throws {
        // Normally 1 every 10 days; one purchase of 3 lasted 30 days.
        let history = ConsumptionHistory(
            category: .paperGoods,
            unit: .pack,
            purchases: [
                .init(date: F.daysAgo(50), quantity: 1, unit: .pack),
                .init(date: F.daysAgo(40), quantity: 3, unit: .pack),
                .init(date: F.daysAgo(10), quantity: 1, unit: .pack),
            ],
            usages: [],
            stock: F.stock(1, unit: .pack)
        )
        let result = try #require(RunOutForecaster.forecast(history, now: F.now))
        #expect(abs(result.dailyRate - 0.1) < 0.001)
        #expect(result.typicalPurchaseQuantity == 1)
    }

    @Test func sameTripPurchasesMerge() throws {
        let purchases = [
            ConsumptionHistory.Purchase(date: F.daysAgo(20), quantity: 1, unit: .each),
            ConsumptionHistory.Purchase(date: F.daysAgo(20).addingTimeInterval(3600), quantity: 1, unit: .each),
            ConsumptionHistory.Purchase(date: F.daysAgo(0), quantity: 2, unit: .each),
        ]
        let result = try forecast(purchases: purchases, stock: F.stock(2))
        #expect(abs(result.dailyRate - 0.1) < 0.001)
    }

    @Test func convertsUnits() throws {
        // Purchases logged in quarts, forecast in gallons.
        let result = try forecast(
            purchases: F.purchases([21, 14, 7, 0], quantity: 4, unit: .quart),
            stock: F.stock(4, unit: .quart),
            unit: .gallon
        )
        #expect(abs(result.dailyRate - 1.0 / 7) < 0.001)
        #expect(abs(result.estimatedRemaining - 1) < 0.001)
    }

    @Test func thinHistoryFallsBackToCategoryDefault() throws {
        let result = try forecast(
            purchases: F.purchases([22]),
            stock: F.stock(1, observedDaysAgo: 22),
            category: .laundry
        )
        #expect(result.basis == .categoryDefault)
        #expect(result.confidence == .low)
        #expect(abs(result.dailyRate - 1.0 / 45) < 0.0001)
        // 22 of 45 days elapsed since the purchase.
        #expect(abs(result.estimatedRemaining - (1 - 22.0 / 45)) < 0.001)
        #expect(abs(result.daysUntilRunOut(from: F.now) - 23) < 0.01)
    }

    @Test func projectsConsumptionSinceLastObservation() throws {
        let fresh = try forecast(purchases: F.purchases([28, 21, 14, 7]), stock: F.stock(1, observedDaysAgo: 0))
        let stale = try forecast(purchases: F.purchases([28, 21, 14, 7]), stock: F.stock(1, observedDaysAgo: 5))
        #expect(abs(fresh.daysUntilRunOut(from: F.now) - 7) < 0.01)
        #expect(abs(stale.daysUntilRunOut(from: F.now) - 2) < 0.01)
    }

    @Test func discardsDoNotCountAsConsumption() throws {
        let tossed = [25.0, 15, 5].map {
            ConsumptionHistory.Usage(date: F.daysAgo($0), quantity: 1, unit: .each, type: .discarded)
        }
        let result = try forecast(purchases: F.purchases([30, 20, 10]), usages: tossed, stock: F.stock(1))
        #expect(result.basis == .purchaseHistory)
        #expect(abs(result.dailyRate - 0.1) < 0.001)
    }

    @Test func partialUseLogsAddAnObservation() throws {
        let logs = [20.0, 15, 10, 5].map {
            ConsumptionHistory.Usage(date: F.daysAgo($0), quantity: 0.5, unit: .each, type: .partiallyUsed)
        }
        let result = try forecast(purchases: F.purchases([21]), usages: logs, stock: F.stock(1))
        // 1.5 units over 15 days.
        #expect(abs(result.dailyRate - 0.1) < 0.001)
        #expect(result.basis == .usage)
    }

    @Test func partialUseIsOnlyAFloorWhenPurchasesAreKnown() throws {
        // Weekly buyer (1/7 per day). Recipe logs cover only part of that.
        let light = [20.0, 13, 6].map {
            ConsumptionHistory.Usage(date: F.daysAgo($0), quantity: 0.25, unit: .each, type: .partiallyUsed)
        }
        let underLogged = try forecast(purchases: F.purchases([21, 14, 7, 0]), usages: light, stock: F.stock(1))
        #expect(abs(underLogged.dailyRate - 1.0 / 7) < 0.001)
        #expect(underLogged.basis == .purchaseHistory)

        // Logs show more use than purchases explain: trust the logs.
        let heavy = [20.0, 15, 10, 5].map {
            ConsumptionHistory.Usage(date: F.daysAgo($0), quantity: 1, unit: .each, type: .partiallyUsed)
        }
        let overLogged = try forecast(purchases: F.purchases([21, 14, 7, 0]), usages: heavy, stock: F.stock(1))
        #expect(abs(overLogged.dailyRate - 0.2) < 0.001)
        #expect(overLogged.basis == .usage)
    }

    @Test func irregularGapsUseTotalAmountOverTotalTime() throws {
        // 3 days, then 11 days: 2 units over 14 days, not the mean of 1/3 and 1/11.
        let result = try forecast(purchases: F.purchases([14, 11, 0]), stock: F.stock(1))
        #expect(abs(result.dailyRate - 2.0 / 14) < 0.02)
        #expect(result.dailyRate < (1.0 / 3 + 1.0 / 11) / 2)
    }

    // MARK: Stock projection

    func stockItem(_ quantity: Double, boughtDaysAgo: Double, observedDaysAgo: Double? = nil, unit: MeasureUnit = .gallon) -> ConsumptionHistory.Stock {
        ConsumptionHistory.Stock(
            id: UUID(),
            quantity: quantity,
            unit: unit,
            observedAt: F.daysAgo(observedDaysAgo ?? boughtDaysAgo),
            acquiredAt: F.daysAgo(boughtDaysAgo)
        )
    }

    @Test func unloggedOlderItemsAreProjectedAsFinished() throws {
        // A gallon every 5 days, never logged: three items still "in stock".
        let items = [stockItem(1, boughtDaysAgo: 11), stockItem(1, boughtDaysAgo: 6), stockItem(1, boughtDaysAgo: 1)]
        let result = try forecast(
            purchases: F.purchases([21, 16, 11, 6, 1], unit: .gallon),
            stock: items,
            unit: .gallon
        )
        #expect(abs(result.dailyRate - 0.2) < 0.02)
        // Only the newest gallon is left, minus a day of use.
        #expect(abs(result.estimatedRemaining - 0.8) < 0.05)
        #expect(result.items.map(\.isProbablyFinished) == [true, true, false])
        #expect(result.items.last?.id == items.last?.id)
    }

    @Test func earlyRestockLeavesTheNewItemUntouched() throws {
        // Weekly buyer restocked after 2 days: the old gallon is still being used.
        let items = [stockItem(1, boughtDaysAgo: 2), stockItem(1, boughtDaysAgo: 0)]
        let result = try forecast(
            purchases: F.purchases([23, 16, 9, 2, 0], unit: .gallon),
            stock: items,
            unit: .gallon
        )
        #expect(abs(result.items[0].remaining - (1 - 2.0 / 7)) < 0.05)
        #expect(result.items[1].remaining == 1)
        #expect(!result.items[1].isProjected)
        #expect(abs(result.estimatedRemaining - (2 - 2.0 / 7)) < 0.05)
    }

    @Test func aRecentCountPinsThatItem() throws {
        // The older item was counted today at half; the newer one hasn't been started.
        let items = [stockItem(0.5, boughtDaysAgo: 12, observedDaysAgo: 0), stockItem(1, boughtDaysAgo: 3)]
        let result = try forecast(
            purchases: F.purchases([26, 19, 12, 3], unit: .gallon),
            stock: items,
            unit: .gallon
        )
        #expect(result.items.map(\.remaining) == [0.5, 1])
        #expect(abs(result.estimatedRemaining - 1.5) < 0.001)
    }

    @Test func itemEstimatesUseEachItemsUnit() throws {
        let item = ConsumptionHistory.Stock(id: UUID(), quantity: 4, unit: .quart, observedAt: F.daysAgo(3.5), acquiredAt: F.daysAgo(3.5))
        let result = try forecast(
            purchases: F.purchases([17.5, 10.5, 3.5], unit: .gallon),
            stock: [item],
            unit: .gallon
        )
        let estimate = try #require(result.items.first)
        #expect(estimate.unit == .quart)
        #expect(estimate.recorded == 4)
        // Half a week of a gallon a week: 2 quarts left.
        #expect(abs(estimate.remaining - 2) < 0.01)
    }

    @Test func estimatesRoundForDisplay() {
        #expect(MeasureUnit.each.roundedEstimate(2.6) == 2.5)
        #expect(MeasureUnit.each.roundedEstimate(0.05) == 0.25)
        #expect(MeasureUnit.gallon.roundedEstimate(0.43) == 0.4)
        #expect(MeasureUnit.gallon.roundedEstimate(0.01) == 0.1)
        #expect(MeasureUnit.ounce.roundedEstimate(23.4) == 23)
        #expect(MeasureUnit.ounce.roundedEstimate(0) == 0)
    }

    @Test func noHistoryAtAllReturnsNil() {
        let history = ConsumptionHistory(category: .dairy, unit: .each, purchases: [], usages: [], stock: [])
        #expect(RunOutForecaster.forecast(history, now: F.now) == nil)
    }

    @Test func sampleDataProducesExpectedConfidence() throws {
        func history(for name: String) throws -> ConsumptionHistory {
            let sample = try #require(SampleData.products.first { $0.name == name })
            return ConsumptionHistory(
                category: sample.category,
                unit: sample.unit,
                purchases: sample.purchases.map { .init(date: F.daysAgo(Double($0.daysAgo)), quantity: $0.quantity, unit: sample.unit) },
                usages: sample.usages.map { .init(date: F.daysAgo(Double($0.daysAgo)), quantity: $0.quantity, unit: sample.unit, type: $0.type) },
                stock: sample.stock.map { [.init(quantity: $0.quantity, unit: sample.unit, observedAt: F.now)] } ?? []
            )
        }
        let milk = try #require(RunOutForecaster.forecast(try history(for: "Whole Milk"), now: F.now))
        #expect(milk.confidence == .high)
        #expect(milk.basis == .usage)
        #expect((3...5).contains(milk.daysUntilRunOut(from: F.now)))

        let toiletPaper = try #require(RunOutForecaster.forecast(try history(for: "Toilet Paper Mega Rolls"), now: F.now))
        #expect(toiletPaper.confidence == .high)
        #expect((12...18).contains(toiletPaper.daysUntilRunOut(from: F.now)))

        let rice = try #require(RunOutForecaster.forecast(try history(for: "Jasmine Rice"), now: F.now))
        #expect(rice.confidence == .low)
        #expect(rice.basis == .categoryDefault)
    }
}

struct ShoppingListGeneratorTests {
    typealias F = ForecastFixtures

    func entry(
        _ name: String,
        runOutInDays: Double,
        remaining: Double = 1,
        confidence: ForecastConfidence = .high,
        purchaseCount: Int = 4,
        lastPurchaseDaysAgo: Double = 7,
        isMarkedLow: Bool = false,
        typical: Double = 2
    ) -> ProductForecast {
        let runOut = F.now.addingTimeInterval(runOutInDays * 86_400)
        let forecast = RunOutForecast(
            dailyRate: 0.1, unit: .each, estimatedRemaining: remaining, runOutDate: runOut,
            earliest: runOut, latest: runOut, confidence: confidence, basis: .purchaseHistory,
            observationCount: 4, typicalPurchaseQuantity: typical
        )
        return ProductForecast(
            productID: UUID(), name: name, category: .dairy, forecast: forecast,
            purchaseCount: purchaseCount, lastPurchaseDate: F.daysAgo(lastPurchaseDaysAgo), isMarkedLow: isMarkedLow
        )
    }

    @Test func includesItemsRunningOutWithinHorizon() {
        let result = ShoppingListGenerator.suggestions(
            from: [entry("Milk", runOutInDays: 3), entry("Rice", runOutInDays: 40)],
            now: F.now
        )
        #expect(result.map(\.name) == ["Milk"])
        #expect(result.first?.quantity == 2)
        #expect(result.first?.reason == .runningOut(F.now.addingTimeInterval(3 * 86_400)))
    }

    @Test func lowConfidenceNeedsTheItemMarkedLow() {
        let result = ShoppingListGenerator.suggestions(
            from: [
                entry("Guess", runOutInDays: 2, confidence: .low),
                entry("Soap", runOutInDays: 2, confidence: .low, isMarkedLow: true),
            ],
            now: F.now
        )
        #expect(result.map(\.name) == ["Soap"])
    }

    @Test func outOfStockRegularsComeFirst() {
        let result = ShoppingListGenerator.suggestions(
            from: [
                entry("Milk", runOutInDays: 3),
                entry("Coffee", runOutInDays: 0, remaining: 0),
                entry("One-off", runOutInDays: 0, remaining: 0, purchaseCount: 1),
                entry("Old habit", runOutInDays: 0, remaining: 0, lastPurchaseDaysAgo: 200),
            ],
            now: F.now
        )
        #expect(result.map(\.name) == ["Coffee", "Milk"])
        #expect(result.first?.reason == .outOfStock)
    }

    @Test func excludesProductsAlreadyOnTheList() {
        let milk = entry("Milk", runOutInDays: 1)
        let result = ShoppingListGenerator.suggestions(from: [milk], now: F.now, excluding: [milk.productID])
        #expect(result.isEmpty)
    }

    @Test func sortsBySoonestRunOut() {
        let result = ShoppingListGenerator.suggestions(
            from: [entry("B", runOutInDays: 5), entry("A", runOutInDays: 6), entry("C", runOutInDays: 1)],
            now: F.now
        )
        #expect(result.map(\.name) == ["C", "B", "A"])
    }
}

struct NotificationPlannerTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// Noon on 2026-09-23 in New York.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!

    func day(_ offset: Int, hour: Int = 18) -> Date {
        Self.calendar.date(byAdding: .day, value: offset, to: Self.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Self.now)!)!
    }

    /// Heads-up reminders only, unless a test turns toss reminders on.
    func plan(_ events: [UpcomingEvent], settings: NotificationSettings = NotificationSettings(tossRemindersEnabled: false)) -> [PlannedNotification] {
        NotificationPlanner.plan(events: events, settings: settings, now: Self.now, calendar: Self.calendar)
    }

    // MARK: Toss reminders

    let tossOn = NotificationSettings(tossRemindersEnabled: true, tossHour: 18)

    @Test func tossReminderFiresTheEveningAfterTheDate() throws {
        let milk = UUID()
        let result = plan([UpcomingEvent(name: "Milk", date: day(3, hour: 0), kind: .expires, itemID: milk)], settings: tossOn)
        let toss = try #require(result.first { $0.kind == .toss })
        #expect(toss.fireDate == Self.calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 18)))
        #expect(toss.id == "larder.reminder.2026-09-27.toss")
        #expect(toss.title == "Past its date: Milk")
        #expect(toss.body == "It expired yesterday. Toss it next time you're in the kitchen.")
        #expect(toss.itemIDs == [milk])
        #expect(toss.badge == 1)
        // The heads-up reminder is separate and keeps its own ID.
        let headsUp = try #require(result.first { $0.kind == .headsUp })
        #expect(headsUp.id == "larder.reminder.2026-09-24")
    }

    @Test func sameEveningTossesGroupAndCountTheBadge() throws {
        let result = plan([
            UpcomingEvent(name: "Milk", date: day(2), kind: .expires, itemID: UUID()),
            UpcomingEvent(name: "Spinach", date: day(2, hour: 8), kind: .expires, itemID: UUID()),
            UpcomingEvent(name: "Yogurt", date: day(-1), kind: .expires, itemID: UUID()),
        ], settings: tossOn)
        let tosses = result.filter { $0.kind == .toss }
        let evening = try #require(tosses.first { $0.id == "larder.reminder.2026-09-26.toss" })
        #expect(evening.title == "2 items are past their date")
        #expect(evening.body == "Spinach and Milk expired. Toss them next time you're in the kitchen.")
        #expect(evening.itemIDs.count == 2)
        // Yogurt expired too, and hasn't been tossed yet.
        #expect(evening.badge == 3)
    }

    @Test func recentlyExpiredItemsGetTheNextTossTime() throws {
        // Expired 3 days ago; its own toss evening has passed. Noon now, so tonight.
        let result = plan([UpcomingEvent(name: "Bread", date: day(-3), kind: .expires)], settings: tossOn)
        let toss = try #require(result.first)
        #expect(toss.kind == .toss)
        #expect(toss.fireDate == Self.calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 18)))
        #expect(toss.body == "It expired 3 days ago. Toss it next time you're in the kitchen.")
    }

    @Test func longExpiredItemsStopNagging() {
        let result = plan([UpcomingEvent(name: "Mustard", date: day(-20), kind: .expires)], settings: tossOn)
        #expect(result.isEmpty)
    }

    @Test func tossTimeAfterNowRollsToTomorrow() throws {
        let morning = NotificationSettings(tossRemindersEnabled: true, tossHour: 8)
        let result = plan([UpcomingEvent(name: "Bread", date: day(-2), kind: .expires)], settings: morning)
        let toss = try #require(result.first)
        #expect(toss.fireDate == Self.calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 8)))
    }

    @Test func runOutsNeverMakeTossReminders() {
        let result = plan([UpcomingEvent(name: "Coffee", date: day(-1), kind: .runsOut)], settings: tossOn)
        #expect(result.isEmpty)
    }

    @Test func firesLeadDaysBeforeAtTheConfiguredHour() throws {
        let result = plan([UpcomingEvent(name: "Spinach", date: day(4), kind: .expires)])
        let notification = try #require(result.first)
        #expect(notification.fireDate == Self.calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9)))
        #expect(notification.id == "larder.reminder.2026-09-25")
        #expect(notification.title == "Use it soon")
        #expect(notification.body == "Spinach expires in 2 days.")
    }

    @Test func groupsSameDayRemindersIntoOneNotification() throws {
        let result = plan([
            UpcomingEvent(name: "Spinach", date: day(4), kind: .expires),
            UpcomingEvent(name: "Milk", date: day(4, hour: 8), kind: .expires),
            UpcomingEvent(name: "Coffee", date: day(5), kind: .runsOut),
        ])
        let notification = try #require(result.first)
        #expect(result.count == 1)
        #expect(notification.title == "Kitchen check-in")
        #expect(notification.body == "Milk and Spinach expire in 2 days. Coffee may run out in 3 days.")
    }

    @Test func skipsRemindersWhoseTimeHasPassed() {
        let result = plan([
            UpcomingEvent(name: "Yogurt", date: day(1), kind: .expires),
            UpcomingEvent(name: "Bread", date: day(2), kind: .expires),
        ])
        #expect(result.isEmpty)
    }

    @Test func lowConfidenceRunOutsAreIgnored() {
        let result = plan([UpcomingEvent(name: "Rice", date: day(10), kind: .runsOut, confidence: .low)])
        #expect(result.isEmpty)
    }

    @Test func respectsLeadTimesAndHourSettings() throws {
        let settings = NotificationSettings(expiryLeadDays: 1, runOutLeadDays: 5, hour: 18, tossRemindersEnabled: false)
        let result = plan([
            UpcomingEvent(name: "Milk", date: day(3), kind: .expires),
            UpcomingEvent(name: "Coffee", date: day(9), kind: .runsOut),
        ], settings: settings)
        #expect(result.map(\.id) == ["larder.reminder.2026-09-25", "larder.reminder.2026-09-27"])
        #expect(Self.calendar.component(.hour, from: result[0].fireDate) == 18)
        #expect(result[1].title == "Running low")
    }

    @Test func disabledSettingsPlanNothing() {
        let settings = NotificationSettings(isEnabled: false)
        #expect(plan([UpcomingEvent(name: "Milk", date: day(9), kind: .expires)], settings: settings).isEmpty)
    }

    @Test func staysUnderTheSystemLimit() {
        let events = (3..<200).map { UpcomingEvent(name: "Item \($0)", date: day($0), kind: .expires) }
        let result = plan(events)
        #expect(result.count == NotificationPlanner.limit)
        #expect(result.map(\.fireDate) == result.map(\.fireDate).sorted())
    }

    @Test func listFormatting() {
        #expect(NotificationPlanner.list(["A"]) == "A")
        #expect(NotificationPlanner.list(["A", "B", "C"]) == "A, B and C")
        #expect(NotificationPlanner.list(["A", "B", "C", "D", "E"]) == "A, B and 3 more")
    }
}
