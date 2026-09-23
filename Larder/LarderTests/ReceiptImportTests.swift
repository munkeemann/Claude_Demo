import Foundation
import InventoryCore
import SwiftData
import Testing
@testable import Larder

@MainActor
struct ReceiptImportTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    let container: ModelContainer
    let store: InventoryStore

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        store = InventoryStore(context: container.mainContext, now: { Self.now })
        try store.seedLocationsIfNeeded()
    }

    func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try container.mainContext.fetch(FetchDescriptor<T>())
    }

    /// Builds a review the way `ReceiptScanFlow` does.
    func makeReview(hints: [ReceiptHint]? = nil) throws -> ReceiptReview {
        var review = ReceiptReview(
            extraction: SampleReceipt.extraction,
            rawText: SampleReceipt.ocrText,
            hints: try hints ?? store.receiptHints(),
            today: Self.now,
            defaultCurrency: "USD"
        )
        let locations = try store.locations()
        for index in review.lines.indices {
            let kind = review.lines[index].locationKind
            review.lines[index].locationID = locations.first { $0.kind == kind }?.id
        }
        review.purchaseDate = Self.now
        return review
    }

    @Test func importCreatesItemsPurchasesReceiptAndAliases() throws {
        let items = try store.importReceipt(try makeReview())

        #expect(items.count == 13)
        #expect(try fetchAll(Product.self).count == 13)
        let purchases = try fetchAll(PurchaseEvent.self)
        #expect(purchases.count == 13)
        #expect(purchases.allSatisfy { $0.source == .receipt && $0.storeName == "Walmart" && $0.receipt != nil })
        #expect(purchases.compactMap(\.priceCents).reduce(0, +) == 8482)

        let receipt = try #require(try fetchAll(Receipt.self).first)
        #expect(receipt.totalCents == 8766)
        #expect(receipt.purchases?.count == 13)
        #expect(receipt.rawText.contains("GV WHL MLK 1G"))

        let aliases = try fetchAll(ProductAlias.self).filter { $0.kind == .receiptText }
        #expect(aliases.count == 13)
        #expect(aliases.contains { $0.value == "gv whl mlk 1g" && $0.product?.name == "Whole Milk" })
    }

    @Test func importPlacesItemsAndEstimatesExpiry() throws {
        let items = try store.importReceipt(try makeReview())
        let milk = try #require(items.first { $0.product?.name == "Whole Milk" })
        #expect(milk.location?.kind == .fridge)
        #expect(milk.unit == .gallon)
        #expect(milk.expiryDate == Calendar.current.date(byAdding: .day, value: 7, to: Self.now))
        #expect(milk.expiryIsOverride == false, "Receipt expiry is an estimate")
        #expect(milk.product?.shelfLifeFridgeDays == 7)

        let bananas = try #require(items.first { $0.product?.name == "Bananas" })
        #expect(bananas.location?.kind == .pantry)
        #expect(bananas.product?.shelfLifeRoomDays == 5)

        let soap = try #require(items.first { $0.product?.name == "Dish Soap" })
        #expect(soap.expiryDate == nil)
        #expect(soap.location?.kind == .cleaning)
        #expect(soap.product?.packageSizeText == "19.4 fl oz")
    }

    @Test func skippedLinesAreNotImported() throws {
        var review = try makeReview()
        review.lines[0].include = false
        let items = try store.importReceipt(review)
        #expect(items.count == 12)
        #expect(try !fetchAll(Product.self).contains { $0.name == "Whole Milk" })
        #expect(try store.receiptHints().count == 12)
    }

    @Test func secondImportReusesProducts() throws {
        try store.importReceipt(try makeReview())
        let secondReview = try makeReview()
        #expect(secondReview.lines.allSatisfy { $0.origin == .remembered })
        try store.importReceipt(secondReview)

        #expect(try fetchAll(Product.self).count == 13)
        #expect(try fetchAll(InventoryItem.self).count == 26)
        #expect(try fetchAll(PurchaseEvent.self).count == 26)
        #expect(try fetchAll(Receipt.self).count == 2)
    }

    @Test func correctionsAreRememberedForNextTime() throws {
        var first = try makeReview()
        let milkIndex = try #require(first.lines.firstIndex { $0.rawText == "GV WHL MLK 1G" })
        first.lines[milkIndex].name = "2% Reduced Fat Milk"
        first.lines[milkIndex].category = .dairy
        #expect(first.lines[milkIndex].wasCorrected)
        try store.importReceipt(first)

        let hint = try #require(try store.receiptHints().first { $0.key == "gv whl mlk 1g" })
        #expect(hint.name == "2% Reduced Fat Milk")

        // Next scan: Claude still says "Whole Milk", but the correction wins.
        let second = try makeReview()
        let milk = try #require(second.lines.first { $0.rawText == "GV WHL MLK 1G" })
        #expect(milk.name == "2% Reduced Fat Milk")
        #expect(milk.origin == .remembered)
        #expect(milk.matchedProductID == hint.productID)
        try store.importReceipt(second)
        #expect(try fetchAll(Product.self).filter { $0.name.contains("Milk") }.count == 1)
    }

    @Test func reCorrectingMovesTheAlias() throws {
        var first = try makeReview()
        first.lines[0].name = "Milk A"
        try store.importReceipt(first)

        var second = try makeReview()
        second.lines[0].name = "Milk B"
        try store.importReceipt(second)

        let hint = try #require(try store.receiptHints().first { $0.key == "gv whl mlk 1g" })
        #expect(hint.name == "Milk B")
        #expect(try fetchAll(ProductAlias.self).filter { $0.value == "gv whl mlk 1g" }.count == 1)
    }

    @Test func receiptMatchesExistingManualProductByName() throws {
        let manual = try store.addItem(from: ItemDraft(name: "Dish Soap", brand: "Dawn", category: .cleaning), source: .manual)
        try store.importReceipt(try makeReview())
        let soapProducts = try fetchAll(Product.self).filter { $0.name == "Dish Soap" }
        #expect(soapProducts.count == 1)
        #expect(soapProducts.first?.id == manual.product?.id)
        #expect(soapProducts.first?.items?.count == 2)
    }

    @Test func importRejectsInvalidLines() throws {
        var review = try makeReview()
        review.lines[3].name = " "
        #expect(throws: InventoryStoreError.self) {
            try store.importReceipt(review)
        }
        #expect(try fetchAll(Product.self).isEmpty)
    }

    @Test func mockServiceFeedsTheSamePipeline() async throws {
        let extraction = try await MockLLMService().extractReceipt(ReceiptExtractionInput(ocrText: SampleReceipt.ocrText))
        #expect(extraction == SampleReceipt.extraction)
    }
}
