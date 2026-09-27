import Foundation
import InventoryCore
import SwiftData

/// How a person wants expiry dates handled when adding items. Personal:
/// stored on this phone only.
enum ExpiryEntryMode: String, CaseIterable, Identifiable {
    /// Larder estimates from USDA storage times.
    case estimate
    /// After adding, walk through the items that usually have a printed date.
    case scanDates
    /// No date unless one is entered.
    case blank

    var id: String { rawValue }

    var label: String {
        switch self {
        case .estimate: "Estimate for me"
        case .scanDates: "Scan package dates"
        case .blank: "Leave blank"
        }
    }

    var summary: String {
        switch self {
        case .estimate: "Larder estimates each date from USDA storage times. You can still add a package date to any item."
        case .scanDates: "After you add items, Larder asks you to point the camera at each package date. Skip any you like; those get an estimate."
        case .blank: "New items have no expiry date until you add one, so they won't trigger reminders."
        }
    }
}

enum ExpiryPreferences {
    static let modeKey = "expiry.entryMode"

    static var mode: ExpiryEntryMode {
        UserDefaults.standard.string(forKey: modeKey).flatMap(ExpiryEntryMode.init(rawValue:)) ?? .estimate
    }
}

enum ExpiryError: LocalizedError {
    case noFreezer

    var errorDescription: String? {
        switch self {
        case .noFreezer: "Add a freezer under Settings → Storage Locations first."
        }
    }
}

extension InventoryStore {
    // MARK: - Household setting

    /// The home's shared settings, created on first use.
    func householdSettings() throws -> HouseholdSettings {
        if let existing = try context.fetch(FetchDescriptor<HouseholdSettings>()).first {
            return existing
        }
        let settings = HouseholdSettings(now: now())
        context.insert(settings)
        return settings
    }

    func expiryStrictness() -> ExpiryStrictness {
        (try? householdSettings().expiryStrictness) ?? .default
    }

    /// Changes how strictly the whole home reads dates, and updates every
    /// item's date to match.
    func setExpiryStrictness(_ strictness: ExpiryStrictness) throws {
        let settings = try householdSettings()
        guard settings.expiryStrictness != strictness else { return }
        settings.expiryStrictness = strictness
        settings.updatedAt = now()
        try refreshAllExpiries()
    }

    // MARK: - USDA FoodKeeper

    /// Looks up the product's FoodKeeper entry once; 0 records "nothing fits".
    func ensureFoodKeeperMatch(_ product: Product) {
        guard product.foodKeeperID == nil else { return }
        guard product.category.isFood else {
            product.foodKeeperID = 0
            return
        }
        product.foodKeeperID = FoodKeeper.match(name: product.name, brand: product.brand, category: product.category)?.id ?? 0
    }

    /// Points a product at a FoodKeeper entry the person picked (nil: none),
    /// then updates its items.
    func setFoodKeeperEntry(_ entry: FoodKeeperEntry?, for product: Product) throws {
        product.foodKeeperID = entry?.id ?? 0
        product.foodKeeperIsManual = true
        product.updatedAt = now()
        for item in product.items ?? [] where item.status.isActive {
            refreshExpiry(item)
        }
        try context.save()
    }

    // MARK: - Working out dates

    func expiryInputs(for item: InventoryItem) -> ExpiryInputs {
        let category = item.product?.category ?? .other
        let climate = item.location?.climate ?? category.defaultClimate
        return ExpiryInputs(
            category: category,
            foodKeeper: item.product?.foodKeeper,
            productShelfLifeDays: item.product?.shelfLifeDays(for: climate),
            climate: climate,
            purchaseDate: item.purchaseDate,
            climateSince: item.climateSince,
            shelfLifeUsed: item.shelfLifeUsed,
            openedDate: item.openedDate,
            thawedDate: item.thawedDate,
            printedDate: item.printedExpiryDate
        )
    }

    /// How the item's date was worked out, for the item screen.
    func expiryResult(for item: InventoryItem) -> ExpiryResult {
        ExpiryCalculator.compute(expiryInputs(for: item), strictness: expiryStrictness())
    }

    /// Recomputes the item's use-by date. Does not save.
    func refreshExpiry(_ item: InventoryItem, strictness: ExpiryStrictness? = nil) {
        guard !item.expiryIsOverride else { return }
        let date: Date?
        let tracks = item.product?.tracksExpiry ?? false
        // A package date always counts; so does opening something, unless
        // it was added with dates left blank.
        if item.printedExpiryDate == nil && (item.expiryTrackingOff || (!tracks && item.openedDate == nil)) {
            date = nil
        } else {
            if let product = item.product { ensureFoodKeeperMatch(product) }
            date = ExpiryCalculator.compute(expiryInputs(for: item), strictness: strictness ?? expiryStrictness()).date
        }
        if item.expiryDate != date { item.expiryDate = date }
    }

    /// Recomputes every in-stock item's date: at launch, and when the
    /// household's strictness changes. Dates set before package dates were
    /// tracked become package dates.
    func refreshAllExpiries() throws {
        let strictness = expiryStrictness()
        for item in try context.fetch(FetchDescriptor<InventoryItem>()) where item.status.isActive {
            if item.expiryIsOverride {
                item.printedExpiryDate = item.printedExpiryDate ?? item.expiryDate
                item.expiryIsOverride = false
            }
            refreshExpiry(item, strictness: strictness)
        }
        if context.hasChanges { try context.save() }
    }

    /// Before USDA data, shelf-stable food (canned, condiments, grains,
    /// snacks, drinks, spices) got no dates by default. Turns dates on for
    /// those products once; runs at launch.
    func startTrackingShelfStableExpiry(defaults: UserDefaults = .standard) throws {
        let key = "expiry.shelfStableTracking.v1"
        guard !defaults.bool(forKey: key) else { return }
        for product in try context.fetch(FetchDescriptor<Product>())
        where !product.tracksExpiry && product.category.isFood && !product.category.isPerishable {
            product.tracksExpiry = true
            product.updatedAt = now()
        }
        if context.hasChanges { try context.save() }
        defaults.set(true, forKey: key)
    }

    // MARK: - Moving, opening, freezing

    /// Moves an item, carrying over how much of its shelf life is used.
    /// Leaving the freezer starts the thawed clock; entering it starts the
    /// freezer clock. Does not save.
    func move(_ item: InventoryItem, to location: StorageLocation?, opened: Bool = false) {
        let category = item.product?.category ?? .other
        let oldClimate = item.location?.climate ?? category.defaultClimate
        let newClimate = location?.climate ?? category.defaultClimate
        if oldClimate != newClimate {
            let when = now()
            switch (oldClimate, newClimate) {
            case (.freezer, _):
                item.thawedDate = when
            case (_, .freezer):
                item.thawedDate = nil
            default:
                if item.thawedDate == nil {
                    item.shelfLifeUsed = ExpiryCalculator.shelfLifeUsed(expiryInputs(for: item), at: when, strictness: expiryStrictness())
                }
            }
            item.climateSince = when
        }
        item.location = location
        if opened, item.openedDate == nil { item.openedDate = now() }
        item.updatedAt = now()
        refreshExpiry(item)
    }

    /// Moves an item and saves.
    func moveItem(_ item: InventoryItem, to location: StorageLocation?, opened: Bool = false) throws {
        move(item, to: location, opened: opened)
        try context.save()
    }

    /// Whether moving the item to `location` is worth asking "did you open
    /// it?": sealed food going from the pantry into the fridge.
    func shouldAskIfOpened(_ item: InventoryItem, movingTo location: StorageLocation?) -> Bool {
        guard item.openedDate == nil, let product = item.product, product.category.isFood else { return false }
        let from = item.location?.climate ?? product.category.defaultClimate
        return from == .room && location?.climate == .fridge
    }

    /// Records the date printed on the package (nil clears it).
    func setPackageDate(_ item: InventoryItem, _ date: Date?) throws {
        item.printedExpiryDate = date
        item.expiryIsOverride = false
        if date != nil { item.expiryTrackingOff = false }
        item.updatedAt = now()
        refreshExpiry(item)
        try context.save()
    }

    func setOpened(_ item: InventoryItem, _ opened: Date?) throws {
        item.openedDate = opened
        item.updatedAt = now()
        refreshExpiry(item)
        try context.save()
    }

    /// The home's freezer: the built-in one, else any freezer-cold location.
    func freezerLocation() throws -> StorageLocation? {
        let all = try locations()
        return all.first { $0.isBuiltIn && $0.climate == .freezer } ?? all.first { $0.climate == .freezer }
    }

    /// Moves an item into the freezer, restarting its clock on USDA's
    /// freezer time.
    func freeze(_ item: InventoryItem) throws {
        guard let freezer = try freezerLocation() else { throw ExpiryError.noFreezer }
        try moveItem(item, to: freezer)
    }

    func freeze(_ ids: [UUID]) throws -> Int {
        var count = 0
        for id in ids {
            guard let item = try self.item(id: id), item.status.isActive, item.location?.climate != .freezer else { continue }
            guard let freezer = try freezerLocation() else { throw ExpiryError.noFreezer }
            move(item, to: freezer)
            count += 1
        }
        try context.save()
        return count
    }
}
