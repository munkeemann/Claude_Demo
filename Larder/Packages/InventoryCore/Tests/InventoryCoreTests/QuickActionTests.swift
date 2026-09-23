import Foundation
import Testing
@testable import InventoryCore

struct QuickActionTests {
    let milk = ItemState(quantity: 1, initialQuantity: 1, unit: .gallon, status: .inStock)
    let cans = ItemState(quantity: 4, initialQuantity: 4, unit: .can, status: .inStock)

    @Test func usedSomeReducesQuantityAndLogsPartialUse() {
        let result = QuickActionCalculator.apply(.usedSome(0.5), to: milk)
        #expect(result.quantity == 0.5)
        #expect(result.status == .inStock)
        #expect(result.usageType == .partiallyUsed)
        #expect(result.usageQuantity == 0.5)
    }

    @Test func usedSomeMarksLowAtQuarterRemaining() {
        let result = QuickActionCalculator.apply(.usedSome(3), to: cans)
        #expect(result.quantity == 1)
        #expect(result.status == .low)
    }

    @Test func usingEverythingCountsAsUsedUp() {
        let result = QuickActionCalculator.apply(.usedSome(5), to: cans)
        #expect(result.quantity == 0)
        #expect(result.status == .usedUp)
        #expect(result.usageType == .usedUp)
        #expect(result.usageQuantity == 4)
    }

    @Test func negativeAmountsAreIgnored() {
        let result = QuickActionCalculator.apply(.usedSome(-2), to: cans)
        #expect(result.quantity == 4)
        #expect(result.usageQuantity == 0)
    }

    @Test func usedUpLogsRemainingQuantity() {
        let partial = ItemState(quantity: 0.6, initialQuantity: 1, unit: .gallon, status: .inStock)
        let result = QuickActionCalculator.apply(.usedUp, to: partial)
        #expect(result.quantity == 0)
        #expect(result.status == .usedUp)
        #expect(result.usageType == .usedUp)
        #expect(result.usageQuantity == 0.6)
    }

    @Test func tossedLogsDiscard() {
        let result = QuickActionCalculator.apply(.tossed, to: milk)
        #expect(result.quantity == 0)
        #expect(result.status == .discarded)
        #expect(result.usageType == .discarded)
        #expect(result.usageQuantity == 1)
    }

    @Test func statusForQuantity() {
        #expect(QuickActionCalculator.status(forQuantity: 0, initialQuantity: 4) == .usedUp)
        #expect(QuickActionCalculator.status(forQuantity: 1, initialQuantity: 4) == .low)
        #expect(QuickActionCalculator.status(forQuantity: 2, initialQuantity: 4) == .inStock)
        #expect(QuickActionCalculator.status(forQuantity: 5, initialQuantity: 0) == .inStock)
    }

    @Test func suggestedUseAmounts() {
        #expect(QuickActionCalculator.suggestedUseAmount(for: cans) == 1)
        let lastBox = ItemState(quantity: 1, initialQuantity: 2, unit: .box, status: .inStock)
        #expect(QuickActionCalculator.suggestedUseAmount(for: lastBox) == 0.5)
        #expect(QuickActionCalculator.suggestedUseAmount(for: milk) == 0.25)
        let yogurt = ItemState(quantity: 5, initialQuantity: 32, unit: .ounce, status: .low)
        #expect(QuickActionCalculator.suggestedUseAmount(for: yogurt) == 5)
    }

    @Test func useSteps() {
        #expect(QuickActionCalculator.useStep(for: cans) == 1)
        #expect(QuickActionCalculator.useStep(for: milk) == 0.1)
        let yogurt = ItemState(quantity: 20, initialQuantity: 32, unit: .ounce, status: .inStock)
        #expect(QuickActionCalculator.useStep(for: yogurt) == 5)
    }
}

struct ExpiryStatusTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    func date(_ day: Int, hour: Int = 12) -> Date {
        Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    @Test(arguments: [
        (9, ExpiryStatus.Urgency.expired, "Expired yesterday"),
        (5, .expired, "Expired 5d ago"),
        (10, .today, "Expires today"),
        (11, .soon, "Tomorrow"),
        (13, .soon, "3 days"),
        (14, .later, "4 days"),
        (31, .later, "3 wks"),
    ])
    func urgencyAndLabel(expiryDay: Int, urgency: ExpiryStatus.Urgency, label: String) {
        let status = ExpiryStatus(expiry: date(expiryDay), now: date(10), calendar: Self.calendar)
        #expect(status.urgency == urgency)
        #expect(status.shortLabel == label)
    }

    @Test func countsCalendarDaysNotHours() {
        // 11pm today → 1am tomorrow is one calendar day.
        let status = ExpiryStatus(expiry: date(11, hour: 1), now: date(10, hour: 23), calendar: Self.calendar)
        #expect(status.daysRemaining == 1)
    }

    @Test func dstTransitionStillCountsWholeDays() {
        // US DST began March 8, 2026.
        let status = ExpiryStatus(expiry: date(9), now: date(7), calendar: Self.calendar)
        #expect(status.daysRemaining == 2)
    }
}
