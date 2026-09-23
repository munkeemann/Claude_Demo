import Foundation
import Testing
@testable import InventoryCore

struct OCRLineAssemblerTests {
    /// Fragment helper using a top-left origin for readability.
    func fragment(_ text: String, x: Double, top: Double, width: Double = 0.2, height: Double = 0.02, confidence: Double = 0.9) -> RecognizedTextFragment {
        RecognizedTextFragment(text: text, x: x, y: 1 - top - height, width: width, height: height, confidence: confidence)
    }

    @Test func joinsNameAndPriceColumnsOnTheSameRow() {
        let fragments = [
            fragment("3.42 N", x: 0.8, top: 0.101),
            fragment("GV WHL MLK 1G", x: 0.05, top: 0.100, width: 0.3),
            fragment("BANANAS", x: 0.05, top: 0.130),
            fragment("1.33 N", x: 0.8, top: 0.131),
        ]
        #expect(OCRLineAssembler.lines(from: fragments) == ["GV WHL MLK 1G    3.42 N", "BANANAS    1.33 N"])
    }

    @Test func toleratesSlightSkew() {
        // Price sits a third of a line lower than the name (a tilted photo).
        let fragments = [
            fragment("BNLS SKNLS CKN BRST", x: 0.05, top: 0.200, width: 0.4),
            fragment("10.29", x: 0.8, top: 0.207),
            fragment("2.10 lb @ 4.90 /lb", x: 0.1, top: 0.225, width: 0.3),
        ]
        #expect(OCRLineAssembler.lines(from: fragments) == ["BNLS SKNLS CKN BRST    10.29", "2.10 lb @ 4.90 /lb"])
    }

    @Test func adjacentFragmentsGetASingleSpace() {
        let fragments = [
            fragment("TOTAL", x: 0.05, top: 0.5, width: 0.1),
            fragment("DUE", x: 0.16, top: 0.5, width: 0.05),
        ]
        #expect(OCRLineAssembler.lines(from: fragments) == ["TOTAL DUE"])
    }

    @Test func dropsLowConfidenceAndBlankFragments() {
        let fragments = [
            fragment("WALMART", x: 0.4, top: 0.02),
            fragment("~~", x: 0.1, top: 0.05, confidence: 0.05),
            fragment("   ", x: 0.1, top: 0.08),
        ]
        #expect(OCRLineAssembler.lines(from: fragments) == ["WALMART"])
    }

    @Test func pagesAreConcatenatedInOrder() {
        let page1 = [fragment("A", x: 0.1, top: 0.1)]
        let page2 = [fragment("B", x: 0.1, top: 0.1)]
        #expect(OCRLineAssembler.text(fromPages: [page1, page2]) == "A\nB")
    }
}

struct ReceiptTextTests {
    @Test(arguments: [
        ("GV WHL MLK 1G    007874237193 F    3.42 N", "gv whl mlk 1g"),
        ("GV WHL MLK 1G", "gv whl mlk 1g"),
        ("gv  whl mlk 1g", "gv whl mlk 1g"),
        ("BANANAS    000000004011 KF    1.33 N", "bananas kf"),
        ("DAWN ULT DISH 19OZ    003700097341    3.47 X", "dawn ult dish 19oz"),
        ("X", "x"),
    ])
    func keys(raw: String, expected: String) {
        #expect(ReceiptText.key(raw) == expected)
    }

    @Test func cents() {
        #expect(ReceiptText.cents(3.42) == 342)
        #expect(ReceiptText.cents(0.1 + 0.2) == 30)
        #expect(ReceiptText.cents(nil) == nil)
        #expect(ReceiptText.cents(.nan) == nil)
    }

    @Test func isoDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = try #require(ReceiptText.date(fromISO: "2026-09-21", calendar: calendar))
        #expect(calendar.component(.day, from: date) == 21)
        #expect(ReceiptText.date(fromISO: "2026-02-30", calendar: calendar) == nil)
        #expect(ReceiptText.date(fromISO: "09/21/26", calendar: calendar) == nil)
        #expect(ReceiptText.date(fromISO: nil, calendar: calendar) == nil)
    }
}

struct ReceiptExtractionTests {
    @Test func sampleExtractionDecodesAndMatchesTotals() {
        let extraction = SampleReceipt.extraction
        #expect(extraction.items.count == 13)
        let itemCents = extraction.items.compactMap { ReceiptText.cents($0.totalPrice) }.reduce(0, +)
        #expect(itemCents == 8482)
        #expect(ReceiptText.cents(extraction.subtotal) == 8482)
        #expect(ReceiptText.cents(extraction.total) == 8766)
        let spaghetti = extraction.items.first { $0.name == "Spaghetti" }
        #expect(spaghetti?.quantity == 2)
        #expect(spaghetti?.unit == .box)
    }

    @Test func sampleExtractionRawTextAppearsOnTheReceipt() {
        let receiptKeys = SampleReceipt.ocrText.split(whereSeparator: \.isNewline).map { ReceiptText.key(String($0)) }
        for item in SampleReceipt.extraction.items {
            let key = ReceiptText.key(item.rawText)
            #expect(receiptKeys.contains { $0.contains(key) }, "\(item.rawText)")
        }
    }

    @Test func decodingIsLenientAboutUnknownEnumsAndBadNumbers() throws {
        let json = """
        {"storeName": null, "purchaseDate": null, "currency": null, "subtotal": null, "tax": null, "total": null,
         "items": [{"rawText": "MYSTERY", "name": "Mystery Item", "brand": "", "category": "gadgets",
                    "quantity": 0, "unit": "bushel", "packageSize": "", "totalPrice": null,
                    "location": "garage", "shelfLifeDays": 4.6, "confidence": "unsure"}]}
        """
        let extraction = try JSONDecoder().decode(ReceiptExtraction.self, from: Data(json.utf8))
        let item = try #require(extraction.items.first)
        #expect(item.category == .other)
        #expect(item.unit == .each)
        #expect(item.quantity == 1)
        #expect(item.brand == nil)
        #expect(item.packageSize == nil)
        #expect(item.location == .pantry)
        #expect(item.shelfLifeDays == 5)
        #expect(item.confidence == .medium)
    }

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
            for keyword in ["minimum", "maximum", "minLength", "maxLength", "multipleOf"] {
                #expect(object[keyword] == nil, "\(path) uses unsupported \(keyword)")
            }
            if let items = object["items"] { check(items, path: "\(path)[]") }
            for option in object["anyOf"]?.arrayValue ?? [] { check(option, path: "\(path)|") }
        }
        check(ReceiptExtractionSchema.schema, path: "$")
    }

    @Test func schemaEnumsMatchSwiftEnums() throws {
        let item = try #require(ReceiptExtractionSchema.schema["properties"]?["items"]?["items"])
        let categories = item["properties"]?["category"]?["enum"]?.arrayValue?.compactMap(\.stringValue)
        #expect(categories == ProductCategory.allCases.map(\.rawValue))
        let locations = item["properties"]?["location"]?["enum"]?.arrayValue?.compactMap(\.stringValue)
        #expect(locations == ["pantry", "fridge", "freezer", "bathroom", "cleaning"])
    }
}

struct ReceiptPromptTests {
    let hints = [
        ReceiptHint(key: "gv whl mlk 1g", productID: UUID(), name: "Whole Milk", brand: "Great Value", category: .dairy, unit: .gallon),
        ReceiptHint(key: "kirkland paper towels", productID: UUID(), name: "Paper Towels", brand: "Kirkland Signature", category: .paperGoods, unit: .pack),
    ]

    @Test func relevantHintsOnlyIncludesTextOnThisReceipt() {
        let relevant = ReceiptPrompt.relevantHints(for: SampleReceipt.ocrText, from: hints)
        #expect(relevant.map(\.name) == ["Whole Milk"])
    }

    @Test func userMessageContainsDateHintsAndReceipt() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 9))!
        let input = ReceiptExtractionInput(ocrText: "GV WHL MLK 1G 3.42", hints: [hints[0]], today: today, currencyCode: "USD")
        let message = ReceiptPrompt.userMessage(for: input, calendar: calendar)
        #expect(message.contains("Today is 2026-09-23"))
        #expect(message.contains("\"gv whl mlk 1g\" → Whole Milk (Great Value), category dairy, unit gal"))
        #expect(message.contains("<receipt>\nGV WHL MLK 1G 3.42\n</receipt>"))
    }

    @Test func systemPromptHasNoVolatileContent() {
        #expect(!ReceiptPrompt.system.contains("Today"))
        #expect(!ReceiptPrompt.system.contains("<receipt>"))
    }
}

struct ReceiptReviewTests {
    static let today: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 9))!
    }()

    func review(hints: [ReceiptHint] = [], extraction: ReceiptExtraction = SampleReceipt.extraction) -> ReceiptReview {
        ReceiptReview(extraction: extraction, rawText: SampleReceipt.ocrText, hints: hints, today: Self.today, defaultCurrency: "EUR")
    }

    @Test func buildsLinesFromExtraction() throws {
        let review = review()
        #expect(review.storeName == "Walmart")
        #expect(review.currencyCode == "USD")
        #expect(review.lines.count == 13)
        #expect(review.lines.allSatisfy { $0.include && $0.origin == .extracted })
        #expect(review.totalsCheck.isConsistent)
        #expect(review.totalsCheck.differenceCents == 0)
        let milk = try #require(review.lines.first)
        #expect(milk.priceCents == 342)
        #expect(milk.locationKind == .fridge)
        #expect(review.canImport)
    }

    @Test func rememberedCorrectionsOverrideClaude() throws {
        let productID = UUID()
        let hint = ReceiptHint(key: "gv whl mlk 1g", productID: productID, name: "Milk (whole)", brand: nil, category: .dairy, unit: .gallon)
        let review = review(hints: [hint])
        let milk = try #require(review.lines.first)
        #expect(milk.name == "Milk (whole)")
        #expect(milk.brand == "")
        #expect(milk.matchedProductID == productID)
        #expect(milk.origin == .remembered)
        #expect(milk.confidence == .high)
        #expect(!milk.wasCorrected, "The remembered mapping is the baseline")
    }

    @Test func detectsUserCorrections() throws {
        var line = try #require(review().lines.first)
        line.quantity = 2
        #expect(!line.wasCorrected, "Quantity edits don't change which product it is")
        line.name = "whole milk"
        #expect(!line.wasCorrected, "Case-only edits are not corrections")
        line.name = "2% Milk"
        #expect(line.wasCorrected)
    }

    @Test func flagsTotalsMismatch() {
        var review = review()
        review.lines.removeLast()
        #expect(!review.totalsCheck.isConsistent)
        #expect(review.totalsCheck.differenceCents == -1397)
    }

    @Test func excludedLinesStillCountTowardTotalsCheck() {
        var review = review()
        review.lines[0].include = false
        #expect(review.totalsCheck.isConsistent)
        #expect(review.includedLines.count == 12)
    }

    @Test func totalsFallBackToTotalMinusTax() {
        var extraction = SampleReceipt.extraction
        extraction.subtotal = nil
        #expect(review(extraction: extraction).totalsCheck.subtotalCents == 8482)
    }

    @Test func invalidLinesBlockImport() {
        var review = review()
        review.lines[2].name = "  "
        #expect(!review.canImport)
        review.lines[2].include = false
        #expect(review.canImport)
    }

    @Test func implausibleDatesFallBackToToday() {
        var extraction = SampleReceipt.extraction
        extraction.purchaseDate = "2019-01-01"
        #expect(review(extraction: extraction).purchaseDate == Self.today)
        extraction.purchaseDate = "2027-01-01"
        #expect(review(extraction: extraction).purchaseDate == Self.today)
        extraction.purchaseDate = nil
        #expect(review(extraction: extraction).purchaseDate == Self.today)
    }

    @Test func draftCarriesEstimatedExpiryForPerishablesOnly() throws {
        let review = review()
        let milk = try #require(review.lines.first { $0.name == "Whole Milk" }).draft(purchaseDate: Self.today)
        #expect(milk.expiryIsEstimate)
        #expect(milk.estimatedShelfLifeDays == 7)
        #expect(milk.expiryDate == Self.today.addingTimeInterval(7 * 86_400))
        #expect(milk.priceCents == 342)
        #expect(milk.unit == .gallon)

        let soap = try #require(review.lines.first { $0.name == "Dish Soap" }).draft(purchaseDate: Self.today)
        #expect(soap.expiryDate == nil)
        #expect(!soap.expiryIsEstimate)
        #expect(soap.packageSizeText == "19.4 fl oz")
    }
}
