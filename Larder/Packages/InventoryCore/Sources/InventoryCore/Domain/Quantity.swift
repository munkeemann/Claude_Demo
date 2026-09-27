/// A value paired with its unit.
public struct Quantity: Hashable, Codable, Sendable {
    public var value: Double
    public var unit: MeasureUnit

    public init(_ value: Double, _ unit: MeasureUnit) {
        self.value = value
        self.unit = unit
    }

    public func converted(to other: MeasureUnit) -> Quantity? {
        unit.convert(value, to: other).map { Quantity($0, other) }
    }

    public var label: String { unit.label(for: value) }
}
