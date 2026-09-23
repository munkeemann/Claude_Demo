import Foundation
import InventoryCore
import SwiftData
import Testing
@testable import Larder

@MainActor
struct InventoryStoreTests {
    let container: ModelContainer
    let store: InventoryStore
    static let now = Date(timeIntervalSince1970: 1_780_000_000)
    var fixedNow: Date { Self.now }

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        store = InventoryStore(context: container.mainContext, now: { Self.now })
        try store.seedLocationsIfNeeded()
    }

    var context: ModelContext { container.mainContext }

    func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    // MARK: Locations

    @Test func seedsBuiltInLocationsOnce() throws {
        try store.seedLocationsIfNeeded()
        let locations = try store.locations()
        #expect(locations.map(\.kind) == LocationKind.builtIn)
        #expect(locations.allSatisfy(\.isBuiltIn))
        #expect(locations.first { $0.kind == .freezer }?.climate == .freezer)
    }

    @Test func customLocationsAppendAndCanBeDeleted() throws {
        let garage = try store.addLocation(name: " Garage fridge ", climate: .fridge, systemImage: "car")
        #expect(garage.name == "Garage fridge")
        #expect(garage.sortOrder == LocationKind.builtIn.count)
        #expect(try store.locations().last?.id == garage.id)

        var draft = ItemDraft(name: "Soda", category: .beverages)
        draft.locationID = garage.id
        let item = try store.addItem(from: draft, source: .manual)
        try store.deleteLocation(garage)
        #expect(item.location == nil)
        #expect(try fetchAll(InventoryItem.self).count == 1)
    }

    @Test func builtInLocationsCannotBeDeleted() throws {
        let pantry = try #require(try store.locations().first)
        #expect(throws: InventoryStoreError.self) {
            try store.deleteLocation(pantry)
        }
    }

    @Test func reorderPersistsSortOrder() throws {
        let reversed = Array(try store.locations().reversed())
        try store.reorderLocations(reversed)
        #expect(try store.locations().map(\.kind) == Array(LocationKind.builtIn.reversed()))
    }

    @Test func defaultLocationFollowsCategory() throws {
        #expect(try store.defaultLocation(for: .dairy)?.kind == .fridge)
        #expect(try store.defaultLocation(for: .frozen)?.kind == .freezer)
        #expect(try store.defaultLocation(for: .laundry)?.kind == .cleaning)
        #expect(try store.defaultLocation(for: .grains)?.kind == .pantry)
    }

    // MARK: Adding items

    @Test func addItemCreatesProductItemAndPurchase() throws {
        let fridge = try #require(try store.defaultLocation(for: .dairy))
        let draft = ItemDraft(
            name: "Whole Milk", brand: "Great Value", category: .dairy, quantity: 1, unit: .gallon,
            locationID: fridge.id, purchaseDate: fixedNow, priceCents: 342
        )
        let item = try store.addItem(from: draft, source: .manual)

        #expect(item.product?.name == "Whole Milk")
        #expect(item.product?.brand == "Great Value")
        #expect(item.location?.id == fridge.id)
        #expect(item.status == .inStock)
        #expect(item.initialQuantity == 1)
        #expect(item.expiryIsOverride == false)

        let purchases = try fetchAll(PurchaseEvent.self)
        #expect(purchases.count == 1)
        #expect(purchases.first?.priceCents == 342)
        #expect(purchases.first?.source == .manual)
        #expect(purchases.first?.product?.id == item.product?.id)
    }

    @Test func invalidDraftIsRejected() throws {
        #expect(throws: InventoryStoreError.self) {
            try store.addItem(from: ItemDraft(name: " "), source: .manual)
        }
        #expect(try fetchAll(Product.self).isEmpty)
    }

    @Test func reusesProductByNameIgnoringCaseAndPunctuation() throws {
        try store.addItem(from: ItemDraft(name: "Greek Yogurt", brand: "Fage", category: .dairy), source: .manual)
        try store.addItem(from: ItemDraft(name: "greek  yogurt", brand: "FAGE", category: .dairy), source: .manual)
        try store.addItem(from: ItemDraft(name: "Greek Yogurt", brand: "Chobani", category: .dairy), source: .manual)
        #expect(try fetchAll(Product.self).count == 2)
        #expect(try fetchAll(InventoryItem.self).count == 3)
    }

    @Test func barcodeAliasesReuseProductAcrossUPCAndEAN() throws {
        let first = try store.addItem(
            from: ItemDraft(name: "Spaghetti", brand: "Barilla", category: .grains, barcode: "076808280593"),
            source: .barcode
        )
        let second = try store.addItem(
            from: ItemDraft(name: "Barilla Spaghetti No. 5", category: .grains, barcode: "0076808280593"),
            source: .barcode
        )
        #expect(first.product?.id == second.product?.id)
        #expect(try store.product(forBarcode: "0 76808 28059 3")?.id == first.product?.id)
        #expect(try fetchAll(ProductAlias.self).count == 1)
    }

    @Test func nameMatchAttachesNewBarcode() throws {
        let manual = try store.addItem(from: ItemDraft(name: "Dish Soap", brand: "Dawn", category: .cleaning), source: .manual)
        try store.addItem(
            from: ItemDraft(name: "Dish Soap", brand: "Dawn", category: .cleaning, barcode: "0037000973417"),
            source: .barcode
        )
        #expect(try store.product(forBarcode: "0037000973417")?.id == manual.product?.id)
    }

    @Test func explicitExpiryIsMarkedAsOverride() throws {
        let expiry = fixedNow.addingTimeInterval(5 * 86_400)
        let item = try store.addItem(
            from: ItemDraft(name: "Spinach", category: .produce, purchaseDate: fixedNow, expiryDate: expiry),
            source: .manual
        )
        #expect(item.expiryIsOverride)
        #expect(item.expiryDate == expiry)
    }

    // MARK: Editing

    @Test func updateAppliesProductAndItemChanges() throws {
        let item = try store.addItem(from: ItemDraft(name: "Yogurt", category: .dairy, quantity: 32, unit: .ounce), source: .manual)
        var draft = item.draft
        draft.name = "Greek Yogurt"
        draft.quantity = 6
        draft.notes = "opened"
        try store.update(item, from: draft)

        #expect(item.product?.name == "Greek Yogurt")
        #expect(item.quantity == 6)
        #expect(item.initialQuantity == 32)
        #expect(item.status == .low)
        #expect(item.notes == "opened")
        #expect(try fetchAll(UsageEvent.self).isEmpty, "Edits are corrections, not usage")
    }

    @Test func raisingQuantityRaisesInitialQuantity() throws {
        let item = try store.addItem(from: ItemDraft(name: "Eggs", category: .eggs, quantity: 1, unit: .dozen), source: .manual)
        var draft = item.draft
        draft.quantity = 2
        try store.update(item, from: draft)
        #expect(item.initialQuantity == 2)
        #expect(item.status == .inStock)
    }

    // MARK: Quick actions

    @Test func usedSomeLogsPartialUsage() throws {
        let item = try store.addItem(from: ItemDraft(name: "Beans", category: .canned, quantity: 4, unit: .can), source: .manual)
        try store.apply(.usedSome(3), to: item)

        #expect(item.quantity == 1)
        #expect(item.status == .low)
        let usage = try #require(try fetchAll(UsageEvent.self).first)
        #expect(usage.type == .partiallyUsed)
        #expect(usage.quantity == 3)
        #expect(usage.unit == .can)
        #expect(usage.item?.id == item.id)
        #expect(usage.product?.id == item.product?.id)
        #expect(usage.date == fixedNow)
    }

    @Test func usedUpAndTossedLogEvents() throws {
        let milk = try store.addItem(from: ItemDraft(name: "Milk", category: .dairy, quantity: 1, unit: .gallon), source: .manual)
        let bread = try store.addItem(from: ItemDraft(name: "Bread", category: .bakery), source: .manual)
        try store.apply(.usedUp, to: milk)
        try store.apply(.tossed, to: bread)

        #expect(milk.status == .usedUp)
        #expect(bread.status == .discarded)
        let types = Set(try fetchAll(UsageEvent.self).map(\.type))
        #expect(types == [.usedUp, .discarded])
    }

    @Test func deletingItemKeepsHistory() throws {
        let item = try store.addItem(from: ItemDraft(name: "Milk", category: .dairy), source: .manual)
        try store.apply(.usedSome(0.5), to: item)
        try store.delete(item)

        #expect(try fetchAll(InventoryItem.self).isEmpty)
        #expect(try fetchAll(Product.self).count == 1)
        #expect(try fetchAll(PurchaseEvent.self).count == 1)
        let usage = try #require(try fetchAll(UsageEvent.self).first)
        #expect(usage.item == nil)
    }

    // MARK: Sample data

    @Test func sampleDataLoadsOnceWithHistory() throws {
        try store.loadSampleData()
        try store.loadSampleData()

        let products = try fetchAll(Product.self)
        #expect(products.count == SampleData.products.count)
        let expectedItems = SampleData.products.filter { $0.stock != nil }.count
        #expect(try fetchAll(InventoryItem.self).count == expectedItems)
        let expectedPurchases = SampleData.products.map(\.purchases.count).reduce(0, +)
        #expect(try fetchAll(PurchaseEvent.self).count == expectedPurchases)

        let milk = try #require(products.first { $0.name == "Whole Milk" })
        #expect(milk.barcodes == ["0078742371937"])
        #expect(milk.items?.first?.location?.kind == .fridge)
        #expect(milk.items?.first?.quantity == 0.6)

        let dishSoap = try #require(products.first { $0.name == "Dish Soap" })
        #expect(dishSoap.items?.first?.status == .low)
    }

    @Test func deleteAllDataKeepsLocations() throws {
        try store.loadSampleData()
        try store.deleteAllData()
        #expect(try fetchAll(Product.self).isEmpty)
        #expect(try fetchAll(InventoryItem.self).isEmpty)
        #expect(try fetchAll(PurchaseEvent.self).isEmpty)
        #expect(try fetchAll(UsageEvent.self).isEmpty)
        #expect(try fetchAll(ProductAlias.self).isEmpty)
        #expect(try store.locations().count == LocationKind.builtIn.count)
    }
}
