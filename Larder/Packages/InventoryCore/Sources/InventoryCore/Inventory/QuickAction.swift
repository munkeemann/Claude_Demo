import Foundation

/// One-tap actions available on an inventory item.
public enum QuickAction: Sendable, Equatable {
    /// Used part of the item. The amount is in the item's unit.
    case usedSome(Double)
    case usedUp
    case tossed
}

/// The mutable state of an item that quick actions operate on.
public struct ItemState: Sendable, Equatable {
    public var quantity: Double
    public var initialQuantity: Double
    public var unit: MeasureUnit
    public var status: ItemStatus

    public init(quantity: Double, initialQuantity: Double, unit: MeasureUnit, status: ItemStatus) {
        self.quantity = quantity
        self.initialQuantity = initialQuantity
        self.unit = unit
        self.status = status
    }
}

/// What applying a quick action produces: the item's new state plus the usage
/// event to log.
public struct QuickActionResult: Sendable, Equatable {
    public var quantity: Double
    public var status: ItemStatus
    public var usageType: UsageType
    public var usageQuantity: Double
}

public enum QuickActionCalculator {
    /// An item is "low" once it drops to this fraction of what was bought.
    public static let lowFraction = 0.25
    static let epsilon = 0.0001

    public static func apply(_ action: QuickAction, to state: ItemState) -> QuickActionResult {
        let remaining = max(0, state.quantity)
        switch action {
        case .usedSome(let requested):
            let used = min(max(0, requested), remaining)
            let left = remaining - used
            if left <= epsilon {
                return QuickActionResult(quantity: 0, status: .usedUp, usageType: .usedUp, usageQuantity: used)
            }
            return QuickActionResult(
                quantity: rounded(left),
                status: status(forQuantity: left, initialQuantity: state.initialQuantity),
                usageType: .partiallyUsed,
                usageQuantity: rounded(used)
            )
        case .usedUp:
            return QuickActionResult(quantity: 0, status: .usedUp, usageType: .usedUp, usageQuantity: remaining)
        case .tossed:
            return QuickActionResult(quantity: 0, status: .discarded, usageType: .discarded, usageQuantity: remaining)
        }
    }

    /// Status implied by a quantity. Used after quick actions and manual edits.
    public static func status(forQuantity quantity: Double, initialQuantity: Double) -> ItemStatus {
        if quantity <= epsilon { return .usedUp }
        guard initialQuantity > epsilon else { return .inStock }
        return quantity <= initialQuantity * lowFraction + epsilon ? .low : .inStock
    }

    /// A sensible default for the "used some" amount.
    /// - Discrete units: one unit, or half of what's left when under one.
    /// - Continuous units: a quarter of the original amount, capped at what's left.
    public static func suggestedUseAmount(for state: ItemState) -> Double {
        let remaining = max(0, state.quantity)
        guard remaining > epsilon else { return 0 }
        if state.unit.isDiscrete {
            return remaining > 1 ? 1 : roundToQuarter(remaining / 2)
        }
        let base = state.initialQuantity > epsilon ? state.initialQuantity : remaining
        return min(remaining, rounded(base * 0.25))
    }

    /// The increment for a "used some" stepper.
    public static func useStep(for state: ItemState) -> Double {
        if state.unit.isDiscrete { return state.quantity > 1 ? 1 : 0.25 }
        let base = max(state.initialQuantity, state.quantity)
        switch base {
        case ..<2: return 0.1
        case ..<20: return 0.5
        case ..<200: return 5
        default: return 25
        }
    }

    static func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    static func roundToQuarter(_ value: Double) -> Double {
        max(0.25, (value * 4).rounded() / 4)
    }
}
