import Foundation
import InventoryCore
import SwiftData

/// Why something is on the shopping list.
enum ShoppingReason: String, CaseIterable {
    case manual
    case predicted
    case recipe

    var displayName: String {
        switch self {
        case .manual: "Added by you"
        case .predicted: "Running out"
        case .recipe: "For a recipe"
        }
    }
}

@Model
final class ShoppingListItem {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Double = 1
    var unitRaw: String = "each"
    var reasonRaw: String = "manual"
    var note: String?
    var isChecked: Bool = false
    var addedAt: Date = Date()
    var checkedAt: Date?

    var product: Product?

    init(name: String, quantity: Double, unit: MeasureUnit, reason: ShoppingReason, note: String? = nil, now: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.reasonRaw = reason.rawValue
        self.note = note
        self.addedAt = now
    }

    var unit: MeasureUnit {
        get { MeasureUnit(rawValue: unitRaw) ?? .each }
        set { unitRaw = newValue.rawValue }
    }

    var reason: ShoppingReason {
        get { ShoppingReason(rawValue: reasonRaw) ?? .manual }
        set { reasonRaw = newValue.rawValue }
    }

    var quantityLabel: String { unit.label(for: quantity) }
}
