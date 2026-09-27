import Foundation
import Testing
@testable import InventoryCore

struct ScanOutTests {
    func hint(_ ref: String, _ name: String, brand: String? = nil, quantity: Double = 1, unit: MeasureUnit = .each) -> ShelfScanHint {
        ShelfScanHint(ref: ref, itemID: UUID(), name: name, brand: brand, quantity: quantity, initialQuantity: quantity, unit: unit, locationName: "Fridge")
    }

    @Test func matchesByReferenceThenByName() {
        let spinach = hint("i1", "Baby Spinach")
        let yogurt = hint("i2", "Plain Greek Yogurt", quantity: 32, unit: .ounce)
        let result = ScanOutResult(items: [
            ScanOutItem(name: "Spinach", inventoryRef: "I1"),
            ScanOutItem(name: "Greek Yogurt"),
            ScanOutItem(name: "Mystery Leftovers"),
        ])
        let review = ScanOutReview(result: result, hints: [spinach, yogurt], disposition: .tossed)
        #expect(review.lines.map(\.matchedItemID) == [spinach.itemID, yogurt.itemID, nil])
        #expect(review.lines.map(\.include) == [true, true, false])
        #expect(review.includedLines.count == 2)
        #expect(review.lines[0].action == .tossed)
    }

    @Test func partsBecomePartialActions() {
        let tomatoes = hint("i1", "Roma Tomatoes", quantity: 5)
        let milk = hint("i2", "Whole Milk", quantity: 1, unit: .gallon)
        let result = ScanOutResult(items: [
            ScanOutItem(name: "Tomatoes", inventoryRef: "i1", isAll: false, quantity: 2, unit: .each),
            ScanOutItem(name: "Milk", inventoryRef: "i2", isAll: false, quantity: 64, unit: .fluidOunce),
        ])
        var review = ScanOutReview(result: result, hints: [tomatoes, milk], disposition: .tossed)
        #expect(review.lines[0].action == .tossedSome(2))
        #expect(review.lines[1].action == .tossedSome(0.5))
        review.setDisposition(.used)
        #expect(review.lines[0].action == .usedSome(2))
    }

    @Test func aReferenceIsUsedOnce() {
        let milk = hint("i1", "Whole Milk")
        let result = ScanOutResult(items: [
            ScanOutItem(name: "Milk", inventoryRef: "i1"),
            ScanOutItem(name: "Milk", inventoryRef: "i1"),
        ])
        let review = ScanOutReview(result: result, hints: [milk], disposition: .used)
        #expect(review.lines.compactMap(\.matchedItemID) == [milk.itemID])
    }

    @Test func promptListsInventoryWithLocations() {
        let input = ScanOutInput(images: [Data([1]), Data([2])], disposition: .tossed, hints: [hint("i1", "Whole Milk", brand: "Horizon", unit: .gallon)])
        let text = ScanOutPrompt.userText(for: input)
        #expect(text.contains("These 2 photos show things being thrown away"))
        #expect(text.contains("- i1: Whole Milk (Horizon), 1 gal, Fridge"))
    }

    @Test func sendsEveryPhotoBeforeTheText() async throws {
        let json = String(data: try JSONEncoder().encode(SampleScanOut.result), encoding: .utf8)!
        let http = ScriptedHTTPClient([.respond(status: 200, body: MessagesFixtures.success(text: json))])
        let client = AnthropicClient(http: http, sleep: { _ in }, apiKey: { "sk-ant-test" })
        let service = AnthropicLLMService(client: client, model: { .opus5 })
        let result = try await service.scanOut(ScanOutInput(images: [Data([1]), Data([2])], disposition: .used, hints: []))
        #expect(result.items.count == 3)
        let body = try http.body(at: 0)
        let content = try #require(body["messages"]?.arrayValue?.first?["content"]?.arrayValue)
        #expect(content.map { $0["type"]?.stringValue } == ["image", "image", "text"])
        #expect(body["output_config"]?["format"]?["schema"] == ScanOutSchema.schema)
    }

    @Test func partialTossLogsADiscardAndKeepsTheRest() {
        let state = ItemState(quantity: 4, initialQuantity: 4, unit: .each, status: .inStock)
        let result = QuickActionCalculator.apply(.tossedSome(1), to: state)
        #expect(result.quantity == 3)
        #expect(result.status == .inStock)
        #expect(result.usageType == .discarded)
        #expect(result.usageQuantity == 1)
        let all = QuickActionCalculator.apply(.tossedSome(10), to: state)
        #expect(all.status == .discarded)
        #expect(all.usageQuantity == 4)
    }
}

struct RecipeScanTests {
    @Test func promptListsInventoryAndPages() {
        let input = RecipeScanInput(
            images: [Data([1]), Data([2])],
            items: [RecipeInventoryItem(promptID: "i1", itemID: UUID(), name: "Spaghetti", brand: "Barilla", category: .grains, amount: "2 box")]
        )
        let text = RecipeScanPrompt.userText(for: input)
        #expect(text.contains("These 2 photos are pages of one recipe."))
        #expect(text.contains("- i1 | Spaghetti (Barilla) | 2 box"))
    }

    @Test func decodesARecipeFromPhotos() async throws {
        let json = String(data: try JSONEncoder().encode(SampleScanOut.recipe), encoding: .utf8)!
        let http = ScriptedHTTPClient([.respond(status: 200, body: MessagesFixtures.success(text: json))])
        let client = AnthropicClient(http: http, sleep: { _ in }, apiKey: { "sk-ant-test" })
        let service = AnthropicLLMService(client: client, model: { .opus5 })
        let recipe = try await service.readRecipe(RecipeScanInput(images: [Data([1])], items: []))
        #expect(recipe.title == "Spaghetti Marinara")
        #expect(!RecipeScanPrompt.isEmpty(recipe))
        let body = try http.body(at: 0)
        #expect(body["system"]?.stringValue == RecipeScanPrompt.system)
    }
}

struct QuickAddTests {
    @Test func parsesAmountsUnitsAndSeparators() {
        let items = QuickAddParser.parse("2 lb chicken thighs, a dozen eggs\n3 cans black beans; half a gallon of milk and bananas")
        #expect(items.map(\.name) == ["Chicken Thighs", "Eggs", "Black Beans", "Milk", "Bananas"])
        #expect(items[0].quantity == 2 && items[0].unit == .pound && items[0].category == .meat)
        #expect(items[1].quantity == 1 && items[1].unit == .dozen && items[1].category == .eggs)
        #expect(items[2].quantity == 3 && items[2].unit == .can)
        #expect(items[3].quantity == 0.5 && items[3].unit == .gallon && items[3].category == .dairy)
        #expect(items[4].category == .produce)
    }

    @Test func keepsKnownBrands() {
        let items = QuickAddParser.parse("tillamook sharp cheddar, 2 fage yogurt, trader joe's olive oil, milk", knownBrands: ["Tillamook", "Fage", "Trader Joe's", "Trader"])
        #expect(items.map(\.brand) == ["Tillamook", "Fage", "Trader Joe's", nil])
        #expect(items.map(\.name) == ["Sharp Cheddar", "Yogurt", "Olive Oil", "Milk"])
        #expect(items[0].category == .cheese)
        #expect(items[1].quantity == 2)
        // A brand alone isn't an item name to strip.
        #expect(QuickAddParser.parse("fage", knownBrands: ["Fage"]).first?.name == "Fage")
        #expect(QuickAddPrompt.userText(for: "milk", knownBrands: ["Fage"]).contains("Brands this household buys: Fage."))
    }

    @Test func keepsFoodsWithAndInTheName() {
        #expect(QuickAddParser.parse("half and half").map(\.name) == ["Half And Half"])
        #expect(QuickAddParser.parse("mac and cheese, milk").count == 2)
    }

    @Test func guessesHouseholdGoodsAndStorage() {
        let items = QuickAddParser.parse("paper towels, dish soap, potatoes, lettuce, 12 eggs, 2lb ground beef, frozen peas")
        #expect(items.map(\.category) == [.paperGoods, .cleaning, .produce, .produce, .eggs, .meat, .frozen])
        #expect(items[6].storage == .freezer)
        #expect(items[2].storage == .room)
        #expect(items[3].storage == .fridge)
        #expect(items[4].quantity == 1 && items[4].unit == .dozen)
        #expect(items[5].quantity == 2 && items[5].unit == .pound)
    }

    @Test func linesKeepTheirLocation() {
        let location = UUID()
        let line = QuickAddItem(name: "Milk", category: .dairy, quantity: 1, unit: .gallon, storage: .fridge).line(locationID: location)
        #expect(line.locationID == location)
        #expect(line.draft(locationID: nil, date: Date()).locationID == location)
    }

    @Test func schemaFollowsStructuredOutputRules() {
        func check(_ schema: JSONValue) {
            guard let object = schema.objectValue else { return }
            if object["type"] == "object" {
                #expect(object["additionalProperties"] == false)
                let properties = object["properties"]?.objectValue ?? [:]
                let required = Set(object["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
                #expect(required == Set(properties.keys))
                properties.values.forEach(check)
            }
            if let items = object["items"] { check(items) }
            object["anyOf"]?.arrayValue?.forEach(check)
        }
        check(QuickAddSchema.schema)
        check(ScanOutSchema.schema)
        check(RecipeScanPrompt.schema)
    }
}

struct WasteReportTests {
    static var calendar: Calendar { ExpiryCalculatorTests.calendar }
    static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!

    func day(_ month: Int, _ day: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    @Test func groupsByMonthAndPricesWhatWasTossed() {
        let spinach = UUID(), milk = UUID(), beans = UUID()
        let usages = [
            WasteReport.Usage(productID: spinach, name: "Baby Spinach", category: .produce, date: day(9, 5), quantity: 1, unit: .each, type: .discarded),
            WasteReport.Usage(productID: milk, name: "Whole Milk", category: .dairy, date: day(9, 12), quantity: 64, unit: .fluidOunce, type: .discarded),
            WasteReport.Usage(productID: beans, name: "Black Beans", category: .canned, date: day(9, 14), quantity: 1, unit: .can, type: .usedUp),
            WasteReport.Usage(productID: spinach, name: "Baby Spinach", category: .produce, date: day(8, 20), quantity: 1, unit: .each, type: .discarded),
            WasteReport.Usage(productID: beans, name: "Black Beans", category: .canned, date: day(3, 1), quantity: 1, unit: .can, type: .discarded),
        ]
        let purchases = [
            WasteReport.Purchase(productID: spinach, date: day(9, 1), quantity: 1, unit: .each, priceCents: 398),
            WasteReport.Purchase(productID: milk, date: day(9, 1), quantity: 1, unit: .gallon, priceCents: 400),
        ]
        let report = WasteReport.build(usages: usages, purchases: purchases, monthCount: 3, now: Self.now, calendar: Self.calendar)
        #expect(report.months.map(\.start) == [day(9, 1), day(8, 1), day(7, 1)])
        let september = try! #require(report.thisMonth)
        #expect(september.tossedCount == 2)
        #expect(september.usedUpCount == 1)
        // Spinach $3.98 plus half a gallon of $4.00 milk.
        #expect(september.tossedCents == 598)
        #expect(!september.hasUnpricedItems)
        #expect(september.wasteShare == 2.0 / 3.0)
        #expect(september.topCategories.map(\.category) == [.dairy, .produce])
        // August's spinach is priced from the next purchase; March is out of range.
        #expect(report.months[1].tossedCents == 398)
        #expect(report.months[2].tossedCount == 0)
    }

    @Test func unknownPricesAreFlagged() {
        let usage = WasteReport.Usage(productID: UUID(), name: "Leftovers", category: .leftovers, date: day(9, 3), quantity: 1, unit: .each, type: .discarded)
        let report = WasteReport.build(usages: [usage], purchases: [], monthCount: 1, now: Self.now, calendar: Self.calendar)
        #expect(report.thisMonth?.hasUnpricedItems == true)
        #expect(report.thisMonth?.tossedCents == 0)
    }
}

struct MultiPhotoShelfTests {
    @Test func sendsEveryPhotoAndSaysTheyAreOnePlace() async throws {
        let json = String(data: try JSONEncoder().encode(SampleShelfScan.result), encoding: .utf8)!
        let http = ScriptedHTTPClient([.respond(status: 200, body: MessagesFixtures.success(text: json))])
        let client = AnthropicClient(http: http, sleep: { _ in }, apiKey: { "sk-ant-test" })
        let service = AnthropicLLMService(client: client, model: { .opus5 })
        _ = try await service.scanShelf(ShelfScanInput(images: [Data([1]), Data([2]), Data([3])], locationName: "Fridge"))
        let body = try http.body(at: 0)
        let content = try #require(body["messages"]?.arrayValue?.first?["content"]?.arrayValue)
        #expect(content.map { $0["type"]?.stringValue } == ["image", "image", "image", "text"])
        #expect(content[3]["text"]?.stringValue?.contains("These 3 photos show the same storage place") == true)
    }

    @Test func expiringRemindersCarryTheirItems() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let spinach = UUID()
        let events = [
            UpcomingEvent(name: "Spinach", date: now.addingTimeInterval(4 * 86_400), kind: .expires, itemID: spinach),
            UpcomingEvent(name: "Milk", date: now.addingTimeInterval(6 * 86_400), kind: .runsOut),
        ]
        let plan = NotificationPlanner.plan(events: events, settings: NotificationSettings(expiryLeadDays: 2, runOutLeadDays: 4, tossRemindersEnabled: false), now: now)
        let headsUp = plan.filter { $0.kind == .headsUp }
        #expect(headsUp.flatMap(\.itemIDs) == [spinach])
    }
}
