import Foundation
import Testing
@testable import InventoryCore

struct InventoryFilterTests {
    static let fridge = UUID()
    static let pantry = UUID()
    static let day: TimeInterval = 86_400
    static let base = Date(timeIntervalSince1970: 1_750_000_000)

    let items: [InventoryItemSummary] = [
        InventoryItemSummary(id: UUID(), productName: "Whole Milk", brand: "Great Value", category: .dairy,
                             locationID: fridge, status: .inStock, expiryDate: base + 6 * day, createdAt: base),
        InventoryItemSummary(id: UUID(), productName: "Baby Spinach", brand: "Marketside", category: .produce,
                             locationID: fridge, status: .inStock, expiryDate: base + 1 * day, createdAt: base + 1),
        InventoryItemSummary(id: UUID(), productName: "Spaghetti", brand: "Barilla", category: .grains,
                             locationID: pantry, status: .low, createdAt: base + 2),
        InventoryItemSummary(id: UUID(), productName: "Crème Fraîche", category: .dairy,
                             locationID: fridge, status: .usedUp, createdAt: base + 3),
        InventoryItemSummary(id: UUID(), productName: "Mystery Box", category: .other,
                             locationID: nil, status: .inStock, createdAt: base + 4, notes: "from grandma"),
    ]

    func names(_ result: [InventoryItemSummary]) -> [String] { result.map(\.productName) }

    @Test func defaultFilterHidesUsedUpAndSortsByName() {
        let result = InventoryFilter().apply(items)
        #expect(names(result) == ["Baby Spinach", "Mystery Box", "Spaghetti", "Whole Milk"])
    }

    @Test func searchMatchesWordPrefixesAcrossFields() {
        #expect(names(InventoryFilter(searchText: "milk").apply(items)) == ["Whole Milk"])
        #expect(names(InventoryFilter(searchText: "barill").apply(items)) == ["Spaghetti"])
        #expect(names(InventoryFilter(searchText: "produce").apply(items)) == ["Baby Spinach"])
        #expect(names(InventoryFilter(searchText: "grandma").apply(items)) == ["Mystery Box"])
    }

    @Test func searchRequiresEveryToken() {
        #expect(names(InventoryFilter(searchText: "great milk").apply(items)) == ["Whole Milk"])
        #expect(InventoryFilter(searchText: "great spinach").apply(items).isEmpty)
    }

    @Test func searchIgnoresCaseAndDiacritics() {
        let filter = InventoryFilter(searchText: "CREME", statuses: [])
        #expect(names(filter.apply(items)) == ["Crème Fraîche"])
    }

    @Test func searchDoesNotMatchInsideWords() {
        #expect(InventoryFilter(searchText: "ilk").apply(items).isEmpty)
    }

    @Test func filtersByLocationAndCategory() {
        let byLocation = InventoryFilter(locationIDs: [Self.pantry])
        #expect(names(byLocation.apply(items)) == ["Spaghetti"])
        let byCategory = InventoryFilter(categories: [.dairy, .produce])
        #expect(names(byCategory.apply(items)) == ["Baby Spinach", "Whole Milk"])
    }

    @Test func locationFilterExcludesUnassignedItems() {
        let filter = InventoryFilter(locationIDs: [Self.fridge, Self.pantry])
        #expect(!names(filter.apply(items)).contains("Mystery Box"))
    }

    @Test func emptyStatusSetShowsEverything() {
        #expect(InventoryFilter(statuses: []).apply(items).count == items.count)
    }

    @Test func sortsByExpiryWithUndatedLast() {
        let result = InventoryFilter(sort: .expiry).apply(items)
        #expect(names(result) == ["Baby Spinach", "Whole Milk", "Mystery Box", "Spaghetti"])
    }

    @Test func sortsByRecentlyAdded() {
        let result = InventoryFilter(sort: .recentlyAdded).apply(items)
        #expect(names(result) == ["Mystery Box", "Spaghetti", "Baby Spinach", "Whole Milk"])
    }

    @Test func genericApplyKeepsOriginalElements() {
        struct Row { let summary: InventoryItemSummary; let tag: Int }
        let rows = items.enumerated().map { Row(summary: $1, tag: $0) }
        let result = InventoryFilter(searchText: "spinach").apply(rows) { $0.summary }
        #expect(result.map(\.tag) == [1])
    }

    @Test func activeFilterDetection() {
        #expect(!InventoryFilter(searchText: "x", sort: .expiry).hasActiveFilters)
        #expect(InventoryFilter(categories: [.dairy]).hasActiveFilters)
        #expect(InventoryFilter(statuses: []).hasActiveFilters)
    }
}

struct ItemDraftTests {
    @Test func categoryDefaultsApplyOnInit() {
        let draft = ItemDraft(name: "Milk", category: .dairy)
        #expect(draft.isIngredient)
        #expect(draft.tracksExpiry)
        #expect(draft.tracksRunOut)
        #expect(draft.unit == .each)

        let paper = ItemDraft(name: "TP", category: .paperGoods)
        #expect(!paper.isIngredient)
        #expect(!paper.tracksExpiry)
        #expect(paper.unit == .pack)
    }

    @Test func explicitFlagsOverrideDefaults() {
        let draft = ItemDraft(name: "Wine", category: .beverages, isIngredient: true)
        #expect(draft.isIngredient)
    }

    @Test func validation() {
        #expect(ItemDraft(name: "  ").issues == [.missingName])
        #expect(ItemDraft(name: "Eggs", quantity: 0).issues == [.nonPositiveQuantity])
        let purchase = Date(timeIntervalSince1970: 1_750_000_000)
        let early = ItemDraft(name: "Eggs", purchaseDate: purchase, expiryDate: purchase - 3 * 86_400)
        #expect(early.issues == [.expiryBeforePurchase])
        #expect(ItemDraft(name: "Eggs", purchaseDate: purchase, expiryDate: purchase).isValid)
    }

    @Test func trimsBrand() {
        #expect(ItemDraft(name: "x", brand: "   ").trimmedBrand == nil)
        #expect(ItemDraft(name: "x", brand: " Fage ").trimmedBrand == "Fage")
    }

    @Test func draftFromLookupCountsPackages() {
        let lookup = ProductLookupResult(
            barcode: "0076808280593", name: "Spaghetti", brand: "Barilla", category: .grains,
            packageSize: PackageSize(count: 1, unitSize: Quantity(16, .ounce)), packageSizeText: "16 oz",
            source: .food
        )
        let draft = ItemDraft(lookup: lookup)
        #expect(draft.quantity == 1)
        #expect(draft.unit == .each)
        #expect(draft.packageSizeText == "16 oz")
        #expect(draft.barcode == "0076808280593")
        #expect(draft.isIngredient)
    }
}
