import Foundation
import InventoryCore
import SwiftData
import Testing
@testable import Larder

@MainActor
struct BatchFlowStoreTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    let container: ModelContainer
    let store: InventoryStore

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        var store = InventoryStore(context: container.mainContext, now: { Self.now })
        store.expiryMode = .estimate
        self.store = store
        try store.seedLocationsIfNeeded()
    }

    func location(_ kind: LocationKind) throws -> StorageLocation {
        try #require(try store.locations().first { $0.kind == kind })
    }

    func add(_ name: String, _ category: ProductCategory, quantity: Double = 1, unit: MeasureUnit? = nil, in kind: LocationKind = .fridge, priceCents: Int? = nil) throws -> InventoryItem {
        var draft = ItemDraft(name: name, category: category, quantity: quantity, unit: unit, locationID: try location(kind).id, purchaseDate: Self.now)
        draft.priceCents = priceCents
        return try store.addItem(from: draft, source: .receipt)
    }

    func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try container.mainContext.fetchCount(FetchDescriptor<T>())
    }

    // MARK: Scanning out

    @Test func scanOutTossesAndUsesMatchedItems() throws {
        let spinach = try add("Baby Spinach", .produce)
        let tomatoes = try add("Roma Tomatoes", .produce, quantity: 5, unit: .each)
        let yogurt = try add("Plain Greek Yogurt", .dairy)
        let hints = try store.scanOutHints()
        #expect(hints.count == 3)
        #expect(hints.allSatisfy { $0.locationName == "Fridge" })

        var review = ScanOutReview(result: SampleScanOut.result, hints: hints, disposition: .tossed)
        #expect(review.includedLines.count == 3)
        // The yogurt was finished, not thrown out.
        if let index = review.lines.firstIndex(where: { $0.matchedItemID == yogurt.id }) {
            review.lines[index].disposition = .used
        }
        #expect(try store.applyScanOut(review) == 3)

        #expect(spinach.status == .discarded)
        #expect(tomatoes.quantity == 3)
        #expect(tomatoes.status.isActive)
        #expect(yogurt.status == .usedUp)
        let usages = try container.mainContext.fetch(FetchDescriptor<UsageEvent>())
        #expect(usages.filter { $0.type == .discarded }.count == 2)
    }

    // MARK: Quick Add and barcodes

    @Test func quickAddPlacesEachItemWhereItsKept() throws {
        let items = QuickAddParser.parse("potatoes, milk, frozen peas, paper towels")
        let lines = try store.quickAddLines(items)
        let places = try lines.map { line in try store.location(id: line.locationID)?.kind }
        #expect(places == [.pantry, .fridge, .freezer, .pantry])

        let review = ShelfScanReview(lines: lines, locationID: nil, source: .manual, justBought: true)
        let added = try store.importShelfScan(review)
        #expect(added.count == 4)
        #expect(added.first?.location?.kind == .pantry)
        #expect(try count(PurchaseEvent.self) == 4)
    }

    @Test func barcodeBatchesRememberTheirBarcodes() throws {
        let line = ShelfScanLine(name: "Spaghetti", brand: "Barilla", category: .grains, quantity: 2, unit: .box, locationID: try location(.pantry).id, barcode: "0076808280593")
        let review = ShelfScanReview(lines: [line], locationID: nil, source: .barcode, justBought: true)
        let added = try store.importShelfScan(review)
        #expect(added.first?.quantity == 2)
        #expect(try store.product(forBarcode: "0076808280593")?.name == "Spaghetti")
        let purchase = try #require(try container.mainContext.fetch(FetchDescriptor<PurchaseEvent>()).first)
        #expect(purchase.source == .barcode)
    }

    // MARK: Undo

    @Test func undoRemovesWhatABatchAddedAndRestoresWhatItChanged() throws {
        let milk = try add("Whole Milk", .dairy, quantity: 1, unit: .gallon)
        let before = try count(InventoryItem.self)
        let purchasesBefore = try count(PurchaseEvent.self)
        let checkpoint = try #require(UndoCenter.checkpoint(container.mainContext))

        let lines = try store.quickAddLines(QuickAddParser.parse("eggs, bread"))
        try store.importShelfScan(ShelfScanReview(lines: lines, locationID: nil, source: .manual, justBought: true))
        try store.apply(.usedSome(0.5), to: milk)
        #expect(try count(InventoryItem.self) == before + 2)

        try UndoCenter.restore(checkpoint, context: container.mainContext)
        #expect(try count(InventoryItem.self) == before)
        #expect(try count(PurchaseEvent.self) == purchasesBefore)
        #expect(try count(UsageEvent.self) == 0)
        #expect(milk.quantity == 1)
        #expect(milk.openedDate == nil)
    }

    // MARK: Household setting

    @Test func strictnessTravelsWithTheHousehold() throws {
        let phoneB = try Persistence.makeContainer(inMemory: true)
        let storeB = InventoryStore(context: phoneB.mainContext, now: { Self.now })
        try storeB.seedLocationsIfNeeded()
        _ = try add("Yogurt", .dairy)
        try store.setExpiryStrictness(.veryRelaxed)

        let envelopes = try SyncMapper(context: container.mainContext).envelopes().values
            .sorted { $0.kind.applyOrder < $1.kind.applyOrder }
        for envelope in envelopes {
            try SyncMapper(context: phoneB.mainContext).apply(envelope)
        }
        try phoneB.mainContext.save()
        #expect(try storeB.householdSettings().expiryStrictness == .veryRelaxed)
        #expect(try phoneB.mainContext.fetchCount(FetchDescriptor<HouseholdSettings>()) == 1)
        let yogurt = try #require(try phoneB.mainContext.fetch(FetchDescriptor<InventoryItem>()).first)
        #expect(yogurt.product?.foodKeeperID == 33)
    }

    // MARK: Shelf-stable dates

    @Test func shelfStableFoodStartsGettingDates() throws {
        let beans = try add("Black Beans", .canned, in: .pantry)
        // A product saved when canned goods didn't track expiry.
        beans.product?.tracksExpiry = false
        store.refreshExpiry(beans)
        #expect(beans.expiryDate == nil)
        let defaults = try #require(UserDefaults(suiteName: "larder.tests.\(UUID().uuidString)"))
        try store.startTrackingShelfStableExpiry(defaults: defaults)
        try store.refreshAllExpiries()
        #expect(beans.product?.tracksExpiry == true)
        #expect(beans.expiryDate != nil)
        // Only once: a later choice to turn it off sticks.
        beans.product?.tracksExpiry = false
        try store.startTrackingShelfStableExpiry(defaults: defaults)
        #expect(beans.product?.tracksExpiry == false)
    }

    // MARK: Waste

    @Test func wasteReportPricesTossedFood() throws {
        let spinach = try add("Baby Spinach", .produce, priceCents: 398)
        let bread = try add("Sourdough Bread", .bakery, in: .pantry, priceCents: 550)
        try store.apply(.tossed, to: spinach)
        try store.apply(.usedUp, to: bread)
        let month = try #require(try store.wasteReport().thisMonth)
        #expect(month.tossedCount == 1)
        #expect(month.tossedCents == 398)
        #expect(month.usedUpCount == 1)
    }
}
