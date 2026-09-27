import Foundation

/// Physical dimension of a unit. Conversion is only possible within a
/// dimension, and container units (pack, can, ...) only convert to themselves.
public enum UnitDimension: String, Sendable {
    case count
    case mass
    case volume
    case container
}

/// Units used for inventory quantities. Raw values are persisted and used as
/// enum values in LLM schemas, so treat them as stable identifiers.
public enum MeasureUnit: String, CaseIterable, Codable, Sendable, Identifiable {
    // Count
    case each
    case dozen
    // Containers: sizes vary, so they never convert to another unit
    case pack
    case box
    case bag
    case bottle
    case can
    case jar
    case roll
    // Mass
    case gram = "g"
    case kilogram = "kg"
    case ounce = "oz"
    case pound = "lb"
    // Volume
    case milliliter = "ml"
    case liter = "l"
    case fluidOunce = "fl oz"
    case cup
    case pint = "pt"
    case quart = "qt"
    case gallon = "gal"

    public var id: String { rawValue }

    public var dimension: UnitDimension {
        switch self {
        case .each, .dozen: .count
        case .pack, .box, .bag, .bottle, .can, .jar, .roll: .container
        case .gram, .kilogram, .ounce, .pound: .mass
        case .milliliter, .liter, .fluidOunce, .cup, .pint, .quart, .gallon: .volume
        }
    }

    /// Size of one of this unit in the dimension's base unit
    /// (each, gram, or milliliter). Containers are their own base.
    public var baseFactor: Double {
        switch self {
        case .each: 1
        case .dozen: 12
        case .pack, .box, .bag, .bottle, .can, .jar, .roll: 1
        case .gram: 1
        case .kilogram: 1000
        case .ounce: 28.349523125
        case .pound: 453.59237
        case .milliliter: 1
        case .liter: 1000
        case .fluidOunce: 29.5735295625
        case .cup: 236.5882365
        case .pint: 473.176473
        case .quart: 946.352946
        case .gallon: 3785.411784
        }
    }

    /// Whether quantities naturally step in whole numbers.
    public var isDiscrete: Bool {
        dimension == .count || dimension == .container
    }

    public var symbol: String {
        switch self {
        case .each: "ea"
        case .dozen: "doz"
        default: rawValue
        }
    }

    /// Human-readable label for a quantity, e.g. "2 cans", "1.5 lb", "3".
    public func label(for value: Double) -> String {
        let number = Self.format(value)
        switch self {
        case .each:
            return number
        case .dozen:
            return "\(number) dozen"
        case .pack, .box, .bag, .bottle, .can, .jar, .roll, .cup:
            let plural = value == 1 ? rawValue : (self == .box ? "boxes" : rawValue + "s")
            return "\(number) \(plural)"
        default:
            return "\(number) \(symbol)"
        }
    }

    public func canConvert(to other: MeasureUnit) -> Bool {
        if self == other { return true }
        return dimension == other.dimension && dimension != .container
    }

    /// Converts `value` from this unit to `other`, or returns nil when the
    /// units are incompatible.
    public func convert(_ value: Double, to other: MeasureUnit) -> Double? {
        guard canConvert(to: other) else { return nil }
        if self == other { return value }
        return value * baseFactor / other.baseFactor
    }

    /// Formats a quantity with at most two fraction digits and no trailing zeros.
    public static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    public static let countUnits = allCases.filter { $0.dimension == .count }
    public static let containerUnits = allCases.filter { $0.dimension == .container }
    public static let massUnits = allCases.filter { $0.dimension == .mass }
    public static let volumeUnits = allCases.filter { $0.dimension == .volume }
}
