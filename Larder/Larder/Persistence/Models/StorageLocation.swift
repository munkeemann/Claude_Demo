import Foundation
import InventoryCore
import SwiftData

/// Where items are kept. The five built-in locations are seeded on first
/// launch; users can add custom ones, each with a storage climate that drives
/// shelf-life estimates.
@Model
final class StorageLocation {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = "custom"
    var climateRaw: String = "room"
    var systemImage: String = "shippingbox"
    var sortOrder: Int = 0
    var isBuiltIn: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \InventoryItem.location)
    var items: [InventoryItem]? = []

    init(
        name: String,
        kind: LocationKind,
        climate: StorageClimate,
        systemImage: String,
        sortOrder: Int,
        isBuiltIn: Bool,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.climateRaw = climate.rawValue
        self.systemImage = systemImage
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
        self.createdAt = now
    }

    convenience init(builtIn kind: LocationKind, sortOrder: Int) {
        self.init(
            name: kind.defaultName,
            kind: kind,
            climate: kind.defaultClimate,
            systemImage: kind.systemImage,
            sortOrder: sortOrder,
            isBuiltIn: true
        )
    }

    var kind: LocationKind {
        get { LocationKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var climate: StorageClimate {
        get { StorageClimate(rawValue: climateRaw) ?? .room }
        set { climateRaw = newValue.rawValue }
    }
}
