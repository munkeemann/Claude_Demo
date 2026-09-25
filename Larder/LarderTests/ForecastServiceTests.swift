import Foundation
import InventoryCore
import SwiftData
import Testing
@testable import Larder

@MainActor
struct ForecastServiceTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    let container: ModelContainer
    let store: InventoryStore
    let service: ForecastService

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        store = InventoryStore(context: container.mainContext, now: { Self.now })
        service = ForecastService(context: container.mainContext, now: { Self.now })
        try store.seedLocationsIfNeeded()
    }

    func location(_ kind: LocationKind) throws -> StorageLocation {
        try #require(try store.locations().first { $0.kind == kind })
    }

    func days(_ count: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: count, to: Self.now)!
    }

    // MARK: Usage estimates

    /// Adds a gallon of milk bought `daysAgo` days before now, never logged.
    @discardableResult
    func buyMilk(daysAgo: Int) throws -> InventoryItem {
        var draft = ItemDraft(name: "Milk", category: .dairy, locationID: try location(.fridge).id, purchaseDate: days(-daysAgo))
        draft.unit = .gallon
        return try store.addItem(from: draft, source: .receipt)
    }

    @Test func unloggedOlderGallonsAreProbablyFinished() throws {
        let oldest = try buyMilk(daysAgo: 16)
        let older = try buyMilk(daysAgo: 11)
        try buyMilk(daysAgo: 6)
        let newest = try buyMilk(daysAgo: 1)

        let snapshot = try service.snapshot()
        #expect(snapshot.estimates[oldest.id]?.isProbablyFinished == true)
        #expect(snapshot.estimates[older.id]?.isProbablyFinished == true)
        #expect(snapshot.estimates[newest.id]?.isProbablyFinished == false)
        let milk = try #require(snapshot.forecasts.first { $0.name == "Milk" })
        #expect(milk.forecast.estimatedRemaining < 1)
        let finishedIDs = try service.probablyFinishedItems().map(\.id)
        #expect(finishedIDs.contains(oldest.id))
    }

    @Test func confirmingFinishedClosesTheItemWithoutLoggingUse() throws {
        let item = try buyMilk(daysAgo: 16)
        try buyMilk(daysAgo: 11)
        try store.confirmFinished(item)
        #expect(item.status == .usedUp)
        #expect(item.quantity == 0)
        #expect((item.product?.usages ?? []).isEmpty)
        let finishedIDs = try service.probablyFinishedItems().map(\.id)
        #expect(!finishedIDs.contains(item.id))
    }

    @Test func recountPinsTheEstimate() throws {
        try buyMilk(daysAgo: 16)
        try buyMilk(daysAgo: 11)
        let item = try buyMilk(daysAgo: 6)
        try store.recount(item, quantity: 0.5)
        #expect(item.status == .inStock)
        #expect(item.quantityObservedAt == Self.now)
        let estimate = try #require(try service.snapshot().estimates[item.id])
        #expect(estimate.remaining == 0.5)
        #expect(!estimate.isProjected)

        try store.recount(item, quantity: 0)
        #expect(item.status == .usedUp)
    }

    // MARK: Expiry estimates

    @Test func addingPerishableEstimatesExpiryFromClimate() throws {
        let draft = ItemDraft(name: "Milk", category: .dairy, locationID: try location(.fridge).id, purchaseDate: Self.now)
        let item = try store.addItem(from: draft, source: .manual)
        #expect(item.expiryDate == days(7))
        #expect(!item.expiryIsOverride)
    }

    @Test func productShelfLifeOverridesTable() throws {
        let first = try store.addItem(
            from: ItemDraft(name: "Spinach", category: .produce, locationID: try location(.fridge).id, purchaseDate: Self.now),
            source: .manual
        )
        first.product?.shelfLifeFridgeDays = 4
        let second = try store.addItem(
            from: ItemDraft(name: "Spinach", category: .produce, locationID: try location(.fridge).id, purchaseDate: Self.now),
            source: .manual
        )
        #expect(second.expiryDate == days(4))
    }

    @Test func movingToFreezerReEstimates() throws {
        let item = try store.addItem(
            from: ItemDraft(name: "Chicken", category: .meat, locationID: try location(.fridge).id, purchaseDate: Self.now),
            source: .manual
        )
        #expect(item.expiryDate == days(2))
        var draft = item.draft
        draft.locationID = try location(.freezer).id
        try store.update(item, from: draft)
        #expect(item.expiryDate == days(120))
    }

    @Test func userSetExpiryIsNeverReEstimated() throws {
        let item = try store.addItem(
            from: ItemDraft(name: "Chicken", category: .meat, locationID: try location(.fridge).id,
                            purchaseDate: Self.now, expiryDate: days(5)),
            source: .manual
        )
        var draft = item.draft
        draft.locationID = try location(.freezer).id
        try store.update(item, from: draft)
        #expect(item.expiryDate == days(5))
    }

    @Test func householdGoodsGetNoExpiry() throws {
        let item = try store.addItem(from: ItemDraft(name: "Bleach", category: .cleaning), source: .manual)
        #expect(item.expiryDate == nil)
    }

    @Test func refreshFillsMissingEstimates() throws {
        let item = try store.addItem(from: ItemDraft(name: "Yogurt", category: .dairy, purchaseDate: Self.now), source: .manual)
        item.expiryDate = nil
        try store.refreshEstimatedExpiries()
        #expect(item.expiryDate == days(7))
    }

    // MARK: Forecasts from sample data

    @Test func sampleDataForecasts() throws {
        try store.loadSampleData()
        let forecasts = try service.productForecasts()
        let byName = Dictionary(forecasts.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        let milk = try #require(byName["Whole Milk"])
        #expect(milk.forecast.confidence == .high)
        #expect(milk.forecast.basis == .usage)
        #expect(milk.purchaseCount == 7)
        #expect((3...5).contains(milk.forecast.daysUntilRunOut(from: Self.now)))

        let rice = try #require(byName["Jasmine Rice"])
        #expect(rice.forecast.confidence == .low)

        #expect(forecasts.map(\.forecast.runOutDate) == forecasts.map(\.forecast.runOutDate).sorted())
        #expect(byName["Dish Soap"]?.isMarkedLow == true)
    }

    @Test func quickActionsFeedTheForecast() throws {
        try store.loadSampleData()
        let before = try #require(try service.productForecasts().first { $0.name == "Whole Milk" })
        let milk = try #require(try container.mainContext.fetch(FetchDescriptor<InventoryItem>()).first { $0.product?.name == "Whole Milk" })
        try store.apply(.usedUp, to: milk)
        let after = try #require(try service.productForecasts().first { $0.name == "Whole Milk" })
        #expect(after.forecast.isOutOfStock)
        #expect(after.forecast.observationCount >= before.forecast.observationCount)
    }

    @Test func expiringItemsAreSortedAndBounded() throws {
        try store.loadSampleData()
        let expiring = try service.expiringItems(withinDays: 3)
        let names = expiring.map(\.displayName)
        #expect(names.contains("Baby Spinach"))
        #expect(names.contains("Boneless Skinless Chicken Breast"))
        #expect(!names.contains("Large Eggs"))
        #expect(expiring.compactMap(\.expiryDate) == expiring.compactMap(\.expiryDate).sorted())
    }

    // MARK: Shopping list

    @Test func suggestionsAddToListOnce() throws {
        try store.loadSampleData()
        let suggestions = try service.shoppingSuggestions(horizonDays: 7)
        #expect(suggestions.contains { $0.name == "Whole Milk" })
        let allConfident = suggestions.allSatisfy { $0.confidence >= .medium || $0.reason == .outOfStock }
        #expect(allConfident)

        try store.addSuggestions(suggestions)
        let entries = try store.shoppingItems()
        #expect(entries.count == suggestions.count)
        let allPredicted = entries.allSatisfy { $0.reason == .predicted && $0.product != nil }
        #expect(allPredicted)
        #expect(try service.shoppingSuggestions(horizonDays: 7).isEmpty)

        try store.addSuggestions(suggestions)
        #expect(try store.shoppingItems().count == suggestions.count)
    }

    @Test func manualEntriesDeduplicateByName() throws {
        try store.addToShoppingList(name: "Paper Towels")
        try store.addToShoppingList(name: "  paper towels ")
        #expect(try store.shoppingItems().count == 1)
        #expect(try store.addToShoppingList(name: "   ") == nil)
    }

    @Test func checkingAndClearing() throws {
        let entry = try #require(try store.addToShoppingList(name: "Bananas"))
        try store.addToShoppingList(name: "Coffee")
        try store.setChecked(entry, true)
        #expect(entry.checkedAt == Self.now)
        // A checked entry doesn't block adding the item again.
        try store.addToShoppingList(name: "Bananas")
        #expect(try store.shoppingItems().count == 3)
        try store.clearCheckedShoppingItems()
        #expect(try store.shoppingItems().map(\.name).sorted() == ["Bananas", "Coffee"])
    }

    @Test func upcomingEventsFeedThePlanner() throws {
        try store.loadSampleData()
        let events = try service.upcomingEvents()
        #expect(events.contains { $0.kind == .expires && $0.name == "Baby Spinach" })
        #expect(events.contains { $0.kind == .runsOut && $0.name == "Whole Milk" })
        #expect(!events.contains { $0.name == "Laundry Detergent" && $0.kind == .expires })
        let plan = NotificationPlanner.plan(events: events, settings: NotificationSettings(), now: Self.now)
        #expect(!plan.isEmpty)
        #expect(plan.count <= NotificationPlanner.limit)
    }
}
