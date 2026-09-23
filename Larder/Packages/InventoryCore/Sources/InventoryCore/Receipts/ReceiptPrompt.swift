import Foundation

/// A remembered mapping from receipt text to a confirmed product.
public struct ReceiptHint: Sendable, Hashable {
    /// `ReceiptText.key` of the raw receipt text.
    public var key: String
    public var productID: UUID
    public var name: String
    public var brand: String?
    public var category: ProductCategory
    public var unit: MeasureUnit

    public init(key: String, productID: UUID, name: String, brand: String?, category: ProductCategory, unit: MeasureUnit) {
        self.key = key
        self.productID = productID
        self.name = name
        self.brand = brand
        self.category = category
        self.unit = unit
    }
}

public struct ReceiptExtractionInput: Sendable, Equatable {
    public var ocrText: String
    public var hints: [ReceiptHint]
    public var today: Date
    public var currencyCode: String

    public init(ocrText: String, hints: [ReceiptHint] = [], today: Date = Date(), currencyCode: String = "USD") {
        self.ocrText = ocrText
        self.hints = hints
        self.today = today
        self.currencyCode = currencyCode
    }
}

public enum ReceiptPrompt {
    /// Stable instructions. Everything that varies per receipt goes in the
    /// user message so this prefix stays identical between requests.
    public static let system = """
    You turn grocery and household-goods receipt text into structured inventory data for a home \
    inventory app. The text comes from OCR, so expect misread characters, merged or split columns, \
    and heavy abbreviation (for example "GV WHL MLK 1G" is Great Value Whole Milk, 1 gallon; \
    "BNLS SKNLS CKN BRST" is boneless skinless chicken breast; "5Z" or "16Z" usually means ounces).

    Rules:
    - Output one item per distinct product. If the same product is printed on several lines, merge \
    them: add the quantities and prices.
    - Skip lines that are not products: subtotals, tax, totals, payment and card lines, change, \
    loyalty/points, bag fees, bottle deposits, headers and footers.
    - Apply discount, coupon and "savings" lines to the item they follow by reducing its totalPrice.
    - rawText: copy the item's description exactly as printed on its line (keep abbreviations), \
    but leave out the price, the item/UPC code and single-letter tax flags.
    - name: a clear everyday product name without the brand or size ("Whole Milk", "Baby Spinach").
    - brand: include store brands (GV = Great Value, KS = Kirkland Signature, MKTSD = Marketside). \
    Use null for unbranded produce and meat.
    - quantity/unit: how much was bought, in the unit that makes consumption easy to track.
      - Items sold by weight (a following line like "2.30 lb @ 0.58 /lb"): the weight, in lb, oz, kg or g.
      - Milk and other standard liquid sizes: the volume (1 gallon of milk is quantity 1, unit "gal").
      - Other packaged goods: the number of packages, with unit "each" or the container word \
    (can, jar, box, bag, bottle, pack, roll), and the package size in packageSize.
      - Multi-buy lines like "4 @ 0.99" mean quantity 4.
    - location: where a typical household stores it after purchase (pantry, fridge, freezer, \
    bathroom, cleaning). Bananas, bread, onions and potatoes go in the pantry.
    - shelfLifeDays: for perishable food, typical days until it spoils at that location, \
    unopened. Use null for shelf-stable food and household goods.
    - confidence: "low" when you had to guess what the abbreviation means.
    - If "Known products" are listed, they are this household's confirmed mappings for receipt \
    text. When an item's text matches one, use that product's name, brand and category.
    """

    /// The per-receipt user message.
    public static func userMessage(for input: ReceiptExtractionInput, calendar: Calendar = .current) -> String {
        var sections: [String] = []
        let components = calendar.dateComponents([.year, .month, .day], from: input.today)
        let today = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        sections.append("Today is \(today). Default currency: \(input.currencyCode).")

        if !input.hints.isEmpty {
            let lines = input.hints
                .sorted { $0.key < $1.key }
                .map { hint -> String in
                    let brand = hint.brand.map { " (\($0))" } ?? ""
                    return "- \"\(hint.key)\" → \(hint.name)\(brand), category \(hint.category.rawValue), unit \(hint.unit.rawValue)"
                }
            sections.append("Known products:\n" + lines.joined(separator: "\n"))
        }

        sections.append("Receipt text:\n<receipt>\n\(input.ocrText)\n</receipt>")
        return sections.joined(separator: "\n\n")
    }

    /// Known mappings whose text appears on this receipt. Sending only the
    /// relevant ones keeps the prompt small as the alias table grows.
    public static func relevantHints(for ocrText: String, from hints: [ReceiptHint]) -> [ReceiptHint] {
        let lineKeys = ocrText
            .split(whereSeparator: \.isNewline)
            .map { ReceiptText.key(String($0)) }
            .filter { !$0.isEmpty }
        return hints.filter { hint in
            !hint.key.isEmpty && lineKeys.contains { $0.contains(hint.key) }
        }
    }
}
