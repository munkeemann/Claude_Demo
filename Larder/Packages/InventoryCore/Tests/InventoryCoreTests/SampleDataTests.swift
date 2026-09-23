import Testing
@testable import InventoryCore

struct SampleDataTests {
    @Test func coversEveryBuiltInLocation() {
        let locations = Set(SampleData.products.map(\.location))
        #expect(locations == Set(LocationKind.builtIn))
    }

    @Test func coversFoodAndHousehold() {
        #expect(SampleData.products.contains { $0.category.isFood })
        #expect(SampleData.products.contains { !$0.category.isFood })
    }

    @Test func namesAreUnique() {
        let names = SampleData.products.map { TextNormalizer.key($0.name) }
        #expect(Set(names).count == names.count)
    }

    @Test func stockIsConsistent() {
        for product in SampleData.products {
            guard let stock = product.stock else { continue }
            #expect(stock.quantity > 0, "\(product.name)")
            #expect(stock.quantity <= stock.initialQuantity, "\(product.name)")
            // The current item should correspond to the most recent purchase.
            #expect(product.purchases.map(\.daysAgo).min() == stock.purchasedDaysAgo, "\(product.name)")
        }
    }

    @Test func usedUpEventsFollowAPurchase() {
        for product in SampleData.products {
            let purchaseDays = product.purchases.map(\.daysAgo)
            for usage in product.usages where usage.type == .usedUp {
                #expect(purchaseDays.contains { $0 > usage.daysAgo }, "\(product.name) used up before any purchase")
            }
        }
    }

    @Test func steadyCadenceProducesExpectedDays() {
        let purchases = SampleData.steady(every: 7, count: 3, lastDaysAgo: 2, quantity: 1, priceCents: nil, store: nil)
        #expect(purchases.map(\.daysAgo) == [2, 9, 16])
    }
}
