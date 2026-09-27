import Foundation
import Testing
@testable import InventoryCore

struct ShelfScanTests {
    func hint(_ ref: String, _ name: String, brand: String? = nil, quantity: Double, initial: Double? = nil, unit: MeasureUnit) -> ShelfScanHint {
        ShelfScanHint(ref: ref, itemID: UUID(), name: name, brand: brand, quantity: quantity, initialQuantity: initial ?? quantity, unit: unit)
    }

    // MARK: Schema and decoding

    @Test func schemaFollowsStructuredOutputRules() {
        func check(_ schema: JSONValue, path: String) {
            guard let object = schema.objectValue else { return }
            if object["type"] == "object" {
                #expect(object["additionalProperties"] == false, "\(path) needs additionalProperties: false")
                let properties = object["properties"]?.objectValue ?? [:]
                let required = Set(object["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
                #expect(required == Set(properties.keys), "\(path) must require every property")
                for (key, value) in properties { check(value, path: "\(path).\(key)") }
            }
            if let items = object["items"] { check(items, path: "\(path)[]") }
            for option in object["anyOf"]?.arrayValue ?? [] { check(option, path: "\(path)|") }
        }
        check(ShelfScanSchema.schema, path: "$")
    }

    @Test func decodesLeniently() throws {
        let json = """
        {"items":[{"name":"Mystery Jar","brand":"","category":"pickles","quantity":0,"unit":"crate",
          "packageSize":"","fillLevel":1.7,"inventoryRef":"","shelfLifeDays":4.6,"confidence":"unsure"}]}
        """
        let result = try JSONDecoder().decode(ShelfScanResult.self, from: Data(json.utf8))
        let item = try #require(result.items.first)
        #expect(item.brand == nil)
        #expect(item.category == .other)
        #expect(item.quantity == 1)
        #expect(item.unit == .each)
        #expect(item.packageSize == nil)
        #expect(item.fillLevel == 1)
        #expect(item.inventoryRef == nil)
        #expect(item.shelfLifeDays == 5)
        #expect(item.confidence == .medium)
    }

    @Test func areasAndPlaceAreOptional() throws {
        let json = """
        {"items":[{"name":"Limes","category":"produce","quantity":3,"unit":"each","confidence":"high"}],"place":"garage"}
        """
        let result = try JSONDecoder().decode(ShelfScanResult.self, from: Data(json.utf8))
        #expect(result.items.map(\.name) == ["Limes"])
        #expect(result.areas.isEmpty)
        #expect(result.place == nil)
    }

    @Test func areasAreWrittenBeforeItems() throws {
        // Structured output follows the schema's property order, and requests
        // are sent with sorted keys: Claude surveys the photo, then lists.
        let json = try #require(String(data: try ShelfScanSchema.schema.encoded(), encoding: .utf8))
        let areas = try #require(json.range(of: "\"areas\""))
        let items = try #require(json.range(of: "\"items\""))
        #expect(areas.lowerBound < items.lowerBound)
    }

    @Test func flagsAPhotoOfSomewhereElse() {
        let fridge = ShelfScanResult(items: [], place: .fridge)
        #expect(fridge.mismatchedPlace(comparedTo: .room) == .fridge)
        #expect(fridge.mismatchedPlace(comparedTo: .fridge) == nil)
        #expect(fridge.mismatchedPlace(comparedTo: nil) == nil)
        #expect(ShelfScanResult(items: []).mismatchedPlace(comparedTo: .room) == nil)
    }

    @Test func sampleRoundTrips() throws {
        let data = try JSONEncoder().encode(SampleShelfScan.result)
        #expect(try JSONDecoder().decode(ShelfScanResult.self, from: data) == SampleShelfScan.result)
    }

    // MARK: Prompt

    @Test func userTextListsLocationAndReferences() {
        let input = ShelfScanInput(
            image: Data([1]),
            locationName: "Fridge",
            climate: .fridge,
            hints: [hint("i1", "Whole Milk", brand: "Horizon", quantity: 1, unit: .gallon)]
        )
        let text = ShelfScanPrompt.userText(for: input)
        #expect(text.contains("Picked location: Fridge (fridge temperature)."))
        #expect(text.contains("- i1: Whole Milk (Horizon), last recorded 1 gal, unit gal"))
    }

    @Test func hintsGetShortSequentialReferences() {
        let hints = ShelfScanPrompt.hints(for: [
            (id: UUID(), name: "Milk", brand: nil, quantity: 1, initialQuantity: 1, unit: .gallon),
            (id: UUID(), name: "Eggs", brand: nil, quantity: 8, initialQuantity: 12, unit: .each),
        ])
        #expect(hints.map(\.ref) == ["i1", "i2"])
    }

    // MARK: Review

    @Test func referencedItemsBecomeUpdatesInTheirOwnUnit() throws {
        let milk = hint("i1", "Whole Milk", quantity: 1, unit: .gallon)
        let result = ShelfScanResult(items: [
            ShelfScanItem(name: "Milk", category: .dairy, quantity: 64, unit: .fluidOunce, inventoryRef: "I1"),
        ])
        let review = ShelfScanReview(result: result, hints: [milk], locationID: nil)
        let line = try #require(review.lines.first)
        #expect(line.action == .update)
        #expect(line.matchedItemID == milk.itemID)
        #expect(line.name == "Whole Milk")
        #expect(line.unit == .gallon)
        #expect(line.quantity == 0.5)
        #expect(line.previousQuantity == 1)
        #expect(review.unseen.isEmpty)
    }

    @Test func fillLevelScalesAnOpenedContainer() throws {
        let milk = hint("i1", "Whole Milk", quantity: 1, unit: .gallon)
        let result = ShelfScanResult(items: [
            ShelfScanItem(name: "Whole Milk", category: .dairy, quantity: 1, unit: .gallon, fillLevel: 0.25, inventoryRef: "i1"),
        ])
        let line = try #require(ShelfScanReview(result: result, hints: [milk], locationID: nil).lines.first)
        #expect(line.quantity == 0.25)
    }

    @Test func unknownReferencesFallBackToAUniqueNameMatch() throws {
        let potatoes = hint("i1", "Potatoes", quantity: 6, unit: .each)
        let onions = hint("i2", "Yellow Onions", quantity: 3, unit: .each)
        let result = ShelfScanResult(items: [
            ShelfScanItem(name: "Russet Potatoes", category: .produce, quantity: 4, unit: .each, inventoryRef: "i9"),
        ])
        let review = ShelfScanReview(result: result, hints: [potatoes, onions], locationID: nil)
        let line = try #require(review.lines.first)
        #expect(line.matchedItemID == potatoes.itemID)
        #expect(line.quantity == 4)
        #expect(review.unseen.map(\.hint.itemID) == [onions.itemID])
        #expect(review.unseen.allSatisfy { !$0.markFinished })
    }

    @Test func aReferenceIsNeverUsedTwice() {
        let eggs = hint("i1", "Eggs", quantity: 12, unit: .each)
        let result = ShelfScanResult(items: [
            ShelfScanItem(name: "Eggs", category: .eggs, quantity: 6, unit: .each, inventoryRef: "i1"),
            ShelfScanItem(name: "Eggs", category: .eggs, quantity: 12, unit: .each, inventoryRef: "i1"),
        ])
        let review = ShelfScanReview(result: result, hints: [eggs], locationID: nil)
        #expect(review.lines.map(\.action) == [.update, .add])
    }

    @Test func differentBrandsDontMatchByName() {
        let jif = hint("i1", "Peanut Butter", brand: "Jif", quantity: 1, unit: .jar)
        let result = ShelfScanResult(items: [
            ShelfScanItem(name: "Peanut Butter", brand: "Skippy", category: .condiments, quantity: 1, unit: .jar),
        ])
        #expect(ShelfScanReview(result: result, hints: [jif], locationID: nil).lines.first?.action == .add)
    }

    @Test func containerCountsMatchCountedItems() throws {
        let tomatoes = hint("i1", "Diced Tomatoes", quantity: 5, unit: .each)
        let result = ShelfScanResult(items: [
            ShelfScanItem(name: "Diced Tomatoes", category: .canned, quantity: 3, unit: .can, inventoryRef: "i1"),
        ])
        let line = try #require(ShelfScanReview(result: result, hints: [tomatoes], locationID: nil).lines.first)
        #expect(line.quantity == 3)
        #expect(line.unit == .each)
        #expect(line.confidence == .high)
    }

    @Test func unreadableAmountsKeepTheRecordedOneAtLowConfidence() throws {
        let rice = hint("i1", "Jasmine Rice", quantity: 5, unit: .pound)
        let result = ShelfScanResult(items: [
            ShelfScanItem(name: "Jasmine Rice", category: .grains, quantity: 1, unit: .bag, inventoryRef: "i1"),
        ])
        let line = try #require(ShelfScanReview(result: result, hints: [rice], locationID: nil).lines.first)
        #expect(line.quantity == 5)
        #expect(line.confidence == .low)
    }

    @Test func newOpenedContainersRememberTheirFullSize() throws {
        let result = ShelfScanResult(items: [
            ShelfScanItem(name: "Peanut Butter", category: .condiments, quantity: 1, unit: .jar, fillLevel: 0.5),
            ShelfScanItem(name: "Onions", category: .produce, quantity: 4, unit: .each),
        ])
        let review = ShelfScanReview(result: result, hints: [], locationID: nil)
        #expect(review.lines[0].action == .add)
        #expect(review.lines[0].quantity == 0.5)
        #expect(review.lines[0].fullQuantity == 1)
        #expect(review.lines[1].fullQuantity == nil)
    }

    @Test func importRules() {
        let milk = hint("i1", "Milk", quantity: 1, unit: .gallon)
        var review = ShelfScanReview(
            result: ShelfScanResult(items: [ShelfScanItem(name: "Milk", category: .dairy, quantity: 0, unit: .gallon, inventoryRef: "i1")]),
            hints: [milk],
            locationID: nil
        )
        // A count that says "none left" is a valid update. (Decoding turns 0 into 1, so set it here.)
        review.lines[0].quantity = 0
        #expect(review.lines[0].isValid)
        #expect(review.canImport)

        review.lines[0].include = false
        #expect(!review.canImport)

        var empty = ShelfScanReview(result: ShelfScanResult(items: []), hints: [milk], locationID: nil)
        #expect(!empty.canImport)
        empty.unseen[0].markFinished = true
        #expect(empty.canImport)
    }

    @Test func increaseIsWhatWasAdded() {
        let line = ShelfScanLine(name: "Eggs", category: .eggs, quantity: 18, unit: .each, matchedItemID: UUID(), previousQuantity: 6)
        #expect(line.increase == 12)
        let fewer = ShelfScanLine(name: "Eggs", category: .eggs, quantity: 2, unit: .each, matchedItemID: UUID(), previousQuantity: 6)
        #expect(fewer.increase == 0)
    }

    @Test func draftEstimatesExpiryForPerishables() throws {
        let today = Date(timeIntervalSince1970: 1_790_000_000)
        let line = ShelfScanLine(name: "Russet Potatoes", category: .produce, quantity: 1, unit: .bag, packageSize: "5 lb", shelfLifeDays: 21)
        let draft = line.draft(locationID: nil, date: today)
        #expect(draft.expiryIsEstimate)
        #expect(draft.estimatedShelfLifeDays == 21)
        #expect(draft.expiryDate == Calendar.current.date(byAdding: .day, value: 21, to: today))
        #expect(draft.packageSizeText == "5 lb")
    }

    // MARK: Request

    @Test func sendsTheImageBeforeTheText() async throws {
        let json = String(data: try JSONEncoder().encode(SampleShelfScan.result), encoding: .utf8)!
        let http = ScriptedHTTPClient([.respond(status: 200, body: MessagesFixtures.success(text: json))])
        let client = AnthropicClient(http: http, sleep: { _ in }, apiKey: { "sk-ant-test" })
        let service = AnthropicLLMService(client: client, model: { .opus5 })

        let image = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let result = try await service.scanShelf(ShelfScanInput(image: image, locationName: "Pantry"))
        #expect(result == SampleShelfScan.result)

        let body = try http.body(at: 0)
        #expect(body["system"]?.stringValue == ShelfScanPrompt.system)
        #expect(body["output_config"]?["format"]?["schema"] == ShelfScanSchema.schema)
        let content = try #require(body["messages"]?.arrayValue?.first?["content"]?.arrayValue)
        #expect(content.count == 2)
        #expect(content[0]["type"] == "image")
        #expect(content[0]["source"]?["type"] == "base64")
        #expect(content[0]["source"]?["media_type"] == "image/jpeg")
        #expect(content[0]["source"]?["data"]?.stringValue == image.base64EncodedString())
        #expect(content[1]["type"] == "text")
        #expect(content[1]["text"]?.stringValue?.contains("Pantry") == true)
    }

    @Test func emptyImageSkipsTheCall() async throws {
        let http = ScriptedHTTPClient([])
        let client = AnthropicClient(http: http, sleep: { _ in }, apiKey: { "sk-ant-test" })
        let service = AnthropicLLMService(client: client, model: { .opus5 })
        let result = try await service.scanShelf(ShelfScanInput(image: Data()))
        #expect(result.items.isEmpty)
        #expect(http.requestCount == 0)
    }
}
