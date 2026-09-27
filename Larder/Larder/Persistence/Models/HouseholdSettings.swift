import Foundation
import InventoryCore
import SwiftData

/// Settings everyone in a home shares. There's one, under a fixed ID, so
/// the copies on each phone are the same record once they sync.
@Model
final class HouseholdSettings {
    static let sharedID = UUID(uuidString: "6C4B1E2A-7F0D-4E55-9C3A-4C41A2D0F001")!

    var id: UUID = HouseholdSettings.sharedID
    var expiryStrictnessRaw: Int = ExpiryStrictness.default.rawValue
    var updatedAt: Date = Date()

    init(now: Date = Date()) {
        self.id = Self.sharedID
        self.updatedAt = now
    }

    var expiryStrictness: ExpiryStrictness {
        get { ExpiryStrictness(rawValue: expiryStrictnessRaw) ?? .default }
        set { expiryStrictnessRaw = newValue.rawValue }
    }
}
