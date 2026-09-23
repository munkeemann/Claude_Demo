/// The temperature regime an item is stored in. Shelf-life estimates are keyed
/// by climate rather than by location so custom locations ("Garage fridge")
/// inherit the right defaults.
public enum StorageClimate: String, CaseIterable, Codable, Sendable, Identifiable {
    case room
    case fridge
    case freezer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .room: "Room temperature"
        case .fridge: "Refrigerated"
        case .freezer: "Frozen"
        }
    }
}

/// Built-in storage location kinds. Users can add any number of `.custom`
/// locations, each of which picks a `StorageClimate`.
public enum LocationKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case pantry
    case fridge
    case freezer
    case bathroom
    case cleaning
    case custom

    public var id: String { rawValue }

    public var defaultName: String {
        switch self {
        case .pantry: "Pantry"
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .bathroom: "Bathroom"
        case .cleaning: "Cleaning"
        case .custom: "Other"
        }
    }

    public var defaultClimate: StorageClimate {
        switch self {
        case .fridge: .fridge
        case .freezer: .freezer
        case .pantry, .bathroom, .cleaning, .custom: .room
        }
    }

    public var systemImage: String {
        switch self {
        case .pantry: "cabinet"
        case .fridge: "refrigerator"
        case .freezer: "snowflake"
        case .bathroom: "shower"
        case .cleaning: "bubbles.and.sparkles"
        case .custom: "shippingbox"
        }
    }

    /// The locations seeded on first launch, in display order.
    public static let builtIn: [LocationKind] = [.pantry, .fridge, .freezer, .bathroom, .cleaning]
}
