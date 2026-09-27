import Foundation
import InventoryCore
import SwiftData
import Testing
@testable import Larder

@MainActor
struct ShelfScanImportTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    let container: ModelContainer
    let store: InventoryStore

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        store = InventoryStore(context: container.mainContext, now: { Self.now })
        try store.seedLocationsIfNeeded()
    }

    func pantry() throws -> StorageLocation {
        try #require(try store.locations().first { $0.kind == .pantry })
    }

    func allItems() throws -> [InventoryItem] {
        try container.mainContext.fetch(FetchDescriptor<InventoryItem>())
    }

    func purchases() throws -> [PurchaseEvent] {
        try container.mainContext.fetch(FetchDescriptor<PurchaseEvent>())
    }

    @Test func hintsCoverActiveItemsAtTheLocation() throws {
        let pantryID = try pantry().id
        try store.addItem(from: ItemDraft(name: "Rice", category: .grains, locationID: pantryID, purchaseDate: Self.now), source: .manual)
        let gone = try store.addItem(from: ItemDraft(name: "Beans", category: .canned, locationID: pantryID, purchaseDate: Self.now), source: .manual)
        try store.apply(.usedUp, to: gone)
        try store.addItem(from: ItemDraft(name: "Milk", category: .dairy, purchaseDate: Self.now), source: .manual)

        let hints = try store.shelfScanHints(locationID: pantryID)
        #expect(hints.map(\.name) == ["Rice"])
        #expect(hints.map(\.ref) == ["i1"])
    }

    @Test func stockTakeAddsAndRecountsWithoutLoggingPurchases() throws {
        let pantryID = try pantry().id
        let potatoes = try store.addItem(
            from: ItemDraft(name: "Potatoes", category: .produce, quantity: 8, unit: .each, locationID: pantryID, purchaseDate: Self.now),
            source: .receipt
        )
        let onions = try store.addItem(
            from: ItemDraft(name: "Onions", category: .produce, quantity: 3, unit: .each, locationID: pantryID, purchaseDate: Self.now),
            source: .receipt
        )
        let purchasesBefore = try purchases().count

        let hints = try store.shelfScanHints(locationID: pantryID)
        let result = ShelfScanResult(items: [
            ShelfScanItem(name: "Potatoes", category: .produce, quantity: 5, unit: .each, inventoryRef: hints.first { $0.name == "Potatoes" }?.ref),
            ShelfScanItem(name: "Peanut Butter", brand: "Jif", category: .condiments, quantity: 1, unit: .jar, fillLevel: 0.5),
        ])
        var review = ShelfScanReview(result: result, hints: hints, locationID: pantryID)
        let unseenOnions = try #require(review.unseen.firstIndex { $0.hint.itemID == onions.id })
        review.unseen[unseenOnions].markFinished = true

        try store.importShelfScan(review)

        #expect(potatoes.quantity == 5)
        #expect(potatoes.quantityObservedAt == Self.now)
        #expect(onions.status == .usedUp)
        let peanutButter = try #require(try allItems().first { $0.displayName == "Peanut Butter" })
        #expect(peanutButter.quantity == 0.5)
        #expect(peanutButter.initialQuantity == 1)
        #expect(peanutButter.location?.id == pantryID)
        #expect(try purchases().count == purchasesBefore)
    }

    @Test func justBoughtLogsNewItemsAndIncreases() throws {
        let pantryID = try pantry().id
        let eggs = try store.addItem(
            from: ItemDraft(name: "Eggs", category: .eggs, quantity: 2, unit: .each, locationID: pantryID, purchaseDate: Self.now),
            source: .receipt
        )
        let hints = try store.shelfScanHints(locationID: pantryID)
        let result = ShelfScanResult(items: [
            ShelfScanItem(name: "Eggs", category: .eggs, quantity: 14, unit: .each, inventoryRef: "i1"),
            ShelfScanItem(name: "Russet Potatoes", category: .produce, quantity: 1, unit: .bag, packageSize: "5 lb"),
        ])
        var review = ShelfScanReview(result: result, hints: hints, locationID: pantryID)
        review.justBought = true
        try store.importShelfScan(review)

        #expect(eggs.quantity == 14)
        #expect(eggs.initialQuantity == 14)
        let eggPurchases = (eggs.product?.purchases ?? []).map(\.quantity).sorted()
        #expect(eggPurchases == [2, 12])
        let potatoes = try #require(try allItems().first { $0.displayName == "Russet Potatoes" })
        #expect((potatoes.product?.purchases ?? []).map(\.source) == [.shelfScan])
    }

    @Test func skippedLinesChangeNothing() throws {
        let pantryID = try pantry().id
        let rice = try store.addItem(
            from: ItemDraft(name: "Rice", category: .grains, quantity: 2, unit: .bag, locationID: pantryID, purchaseDate: Self.now),
            source: .receipt
        )
        let hints = try store.shelfScanHints(locationID: pantryID)
        var review = ShelfScanReview(
            result: ShelfScanResult(items: [ShelfScanItem(name: "Rice", category: .grains, quantity: 1, unit: .bag, inventoryRef: "i1")]),
            hints: hints,
            locationID: pantryID
        )
        review.lines[0].include = false
        try store.importShelfScan(review)
        #expect(rice.quantity == 2)
        #expect(rice.quantityObservedAt == nil)
    }
}
