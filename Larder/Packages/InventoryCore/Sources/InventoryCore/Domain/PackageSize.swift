import Foundation

/// A parsed package size such as "1 gal", "500 g", "12 rolls" or "6 x 330 ml".
public struct PackageSize: Hashable, Codable, Sendable {
    /// Number of units in the package ("6" in "6 x 330 ml"). 1 for single items.
    public var count: Int
    /// Size of each unit, when known ("330 ml").
    public var unitSize: Quantity?

    public init(count: Int = 1, unitSize: Quantity?) {
        self.count = count
        self.unitSize = unitSize
    }

    public var label: String {
        switch (count, unitSize) {
        case (1, let size?): size.label
        case (let n, let size?): "\(n) × \(size.label)"
        case (let n, nil): "\(n) ct"
        }
    }

    /// Parses a package size string. Returns nil if nothing recognizable is found.
    public static func parse(_ text: String) -> PackageSize? {
        let lowered = text.lowercased()
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "×", with: "x")
        let tokens = tokenize(lowered)
        guard !tokens.isEmpty else { return nil }

        // Multipack: "<n> x <value> <unit>"
        if tokens.count >= 3,
           case .number(let count) = tokens[0],
           case .word("x") = tokens[1],
           let size = parseQuantity(Array(tokens.dropFirst(2))) {
            return PackageSize(count: max(1, Int(count)), unitSize: size)
        }

        if let size = parseQuantity(tokens) {
            // "12 rolls" / "24 ct" become a count, not a unit size.
            if size.unit == .each || size.unit.dimension == .container {
                return PackageSize(count: max(1, Int(size.value.rounded())), unitSize: nil)
            }
            if size.unit == .dozen {
                return PackageSize(count: max(1, Int((size.value * 12).rounded())), unitSize: nil)
            }
            return PackageSize(count: 1, unitSize: size)
        }
        return nil
    }

    // MARK: - Parsing helpers

    enum Token: Equatable {
        case number(Double)
        case word(String)
    }

    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentIsNumber = false

        func flush() {
            guard !current.isEmpty else { return }
            let numeric = current.hasSuffix(".") ? String(current.dropLast()) : current
            if currentIsNumber, let value = Double(numeric) {
                tokens.append(.number(value))
            } else if !current.allSatisfy({ $0 == "." }) {
                tokens.append(.word(current.trimmingCharacters(in: CharacterSet(charactersIn: "."))))
            }
            current = ""
        }

        for char in text {
            if char.isNumber || (char == "." && currentIsNumber) {
                if !currentIsNumber { flush() }
                currentIsNumber = true
                current.append(char)
            } else if char.isLetter {
                if currentIsNumber { flush() }
                currentIsNumber = false
                current.append(char)
            } else {
                flush()
                currentIsNumber = false
            }
        }
        flush()
        return tokens
    }

    /// Finds the first "<number> <unit>" pair in the tokens.
    static func parseQuantity(_ tokens: [Token]) -> Quantity? {
        for index in tokens.indices {
            guard case .number(let value) = tokens[index] else { continue }
            var words: [String] = []
            var next = tokens.index(after: index)
            while next < tokens.endIndex, case .word(let word) = tokens[next], words.count < 2 {
                words.append(word)
                next = tokens.index(after: next)
            }
            // Try two-word units first ("fl oz"), then one-word.
            if words.count == 2, let unit = unit(for: words.joined(separator: " ")) {
                return Quantity(value, unit)
            }
            if let first = words.first, let unit = unit(for: first) {
                return Quantity(value, unit)
            }
        }
        return nil
    }

    /// Maps unit spellings found on packaging and receipts to `MeasureUnit`.
    public static func unit(for word: String) -> MeasureUnit? {
        switch word.lowercased() {
        case "g", "gr", "gram", "grams", "gm": .gram
        case "kg", "kgs", "kilo", "kilogram", "kilograms": .kilogram
        case "oz", "ounce", "ounces", "onz": .ounce
        case "lb", "lbs", "pound", "pounds": .pound
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres": .milliliter
        case "l", "lt", "ltr", "liter", "liters", "litre", "litres": .liter
        case "fl oz", "floz", "fl. oz", "fluid ounce", "fluid ounces": .fluidOunce
        case "cup", "cups": .cup
        case "pt", "pint", "pints": .pint
        case "qt", "quart", "quarts": .quart
        case "gal", "gallon", "gallons": .gallon
        case "ct", "count", "pc", "pcs", "piece", "pieces", "ea", "each", "unit", "units", "sheets", "bars", "pods", "tablets", "capsules":
            .each
        case "dozen", "doz", "dz": .dozen
        case "pk", "pack", "packs", "pkg": .pack
        case "box", "boxes": .box
        case "bag", "bags": .bag
        case "bottle", "bottles", "btl": .bottle
        case "can", "cans": .can
        case "jar", "jars": .jar
        case "roll", "rolls": .roll
        default: nil
        }
    }
}
