import Foundation
import InventoryCore
import SwiftData

/// Converts between the app's models and shared records (`SyncEnvelope`).
/// Every model a household shares is covered; `SyncRecordState` is local
/// bookkeeping and never shared.
@MainActor
struct SyncMapper {
    let context: ModelContext

    // MARK: - Local → shared

    /// Every shareable object's canonical payload, by record name. Where the
    /// fresh payload differs from the last agreed one, fields and references
    /// this phone can't express are carried over (see
    /// `SyncEnvelope.preserving`).
    func snapshot(agreed: [String: Data]) throws -> [String: Data] {
        let current = try envelopes()
        let names = Set(current.keys)
        var result: [String: Data] = [:]
        result.reserveCapacity(current.count)
        for (name, envelope) in current {
            let fresh = try envelope.encoded()
            guard let previousData = agreed[name], previousData != fresh,
                  let previous = try? SyncEnvelope.decode(previousData)
            else {
                result[name] = fresh
                continue
            }
            let merged = envelope.preserving(from: previous) { names.contains(SyncRecordName.make($0.kind, $0.id)) }
            result[name] = try merged.encoded()
        }
        return result
    }

    /// The payload for one record, or nil if its object no longer exists.
    func payload(kind: SyncKind, id: UUID, agreed: Data?) throws -> Data? {
        guard let current = try self.envelope(kind: kind, id: id) else { return nil }
        let fresh = try current.encoded()
        guard let agreed, agreed != fresh, let previous = try? SyncEnvelope.decode(agreed) else { return fresh }
        let merged = current.preserving(from: previous) { ref in
            (try? exists(ref)) ?? false
        }
        return try merged.encoded()
    }

    func envelopes() throws -> [String: SyncEnvelope] {
        var result: [String: SyncEnvelope] = [:]
        func add(_ envelope: SyncEnvelope) { result[envelope.recordName] = envelope }
        for object in try context.fetch(FetchDescriptor<StorageLocation>()) { add(Self.envelope(object)) }
        for object in try context.fetch(FetchDescriptor<Product>()) { add(Self.envelope(object)) }
        for object in try context.fetch(FetchDescriptor<ProductAlias>()) { add(Self.envelope(object)) }
        for object in try context.fetch(FetchDescriptor<Receipt>()) { add(Self.envelope(object)) }
        for object in try context.fetch(FetchDescriptor<InventoryItem>()) { add(Self.envelope(object)) }
        for object in try context.fetch(FetchDescriptor<PurchaseEvent>()) { add(Self.envelope(object)) }
        for object in try context.fetch(FetchDescriptor<UsageEvent>()) { add(Self.envelope(object)) }
        for object in try context.fetch(FetchDescriptor<ShoppingListItem>()) { add(Self.envelope(object)) }
        for object in try context.fetch(FetchDescriptor<SavedRecipe>()) { add(Self.envelope(object)) }
        return result
    }

    func envelope(kind: SyncKind, id: UUID) throws -> SyncEnvelope? {
        switch kind {
        case .location: try location(id).map { Self.envelope($0) }
        case .product: try product(id).map { Self.envelope($0) }
        case .alias: try alias(id).map { Self.envelope($0) }
        case .receipt: try receipt(id).map { Self.envelope($0) }
        case .item: try item(id).map { Self.envelope($0) }
        case .purchase: try purchase(id).map { Self.envelope($0) }
        case .usage: try usage(id).map { Self.envelope($0) }
        case .shoppingItem: try shoppingItem(id).map { Self.envelope($0) }
        case .savedRecipe: try savedRecipe(id).map { Self.envelope($0) }
        }
    }

    func exists(_ ref: SyncRef) throws -> Bool {
        try envelope(kind: ref.kind, id: ref.id) != nil
    }

    static func envelope(_ location: StorageLocation) -> SyncEnvelope {
        var f = SyncFieldWriter()
        f.set("name", location.name)
        f.set("kind", location.kindRaw)
        f.set("climate", location.climateRaw)
        f.set("systemImage", location.systemImage)
        f.set("sortOrder", location.sortOrder)
        f.set("isBuiltIn", location.isBuiltIn)
        f.set("createdAt", location.createdAt)
        return SyncEnvelope(kind: .location, id: location.id, fields: f.fields)
    }

    static func envelope(_ product: Product) -> SyncEnvelope {
        var f = SyncFieldWriter()
        f.set("name", product.name)
        f.set("brand", product.brand)
        f.set("category", product.categoryRaw)
        f.set("defaultUnit", product.defaultUnitRaw)
        f.set("packageSizeText", product.packageSizeText)
        f.set("imageURL", product.imageURLString)
        f.set("shelfLifeRoomDays", product.shelfLifeRoomDays)
        f.set("shelfLifeFridgeDays", product.shelfLifeFridgeDays)
        f.set("shelfLifeFreezerDays", product.shelfLifeFreezerDays)
        f.set("isIngredient", product.isIngredient)
        f.set("tracksRunOut", product.tracksRunOut)
        f.set("tracksExpiry", product.tracksExpiry)
        f.set("createdAt", product.createdAt)
        f.set("updatedAt", product.updatedAt)
        return SyncEnvelope(kind: .product, id: product.id, fields: f.fields)
    }

    static func envelope(_ alias: ProductAlias) -> SyncEnvelope {
        var f = SyncFieldWriter()
        f.set("kind", alias.kindRaw)
        f.set("value", alias.value)
        f.set("createdAt", alias.createdAt)
        f.set("lastUsedAt", alias.lastUsedAt)
        return SyncEnvelope(kind: .alias, id: alias.id, fields: f.fields, refs: refs(["product": alias.product.map { SyncRef(.product, $0.id) }]))
    }

    static func envelope(_ receipt: Receipt) -> SyncEnvelope {
        var f = SyncFieldWriter()
        f.set("storeName", receipt.storeName)
        f.set("purchaseDate", receipt.purchaseDate)
        f.set("totalCents", receipt.totalCents)
        f.set("currencyCode", receipt.currencyCode)
        f.set("rawText", receipt.rawText)
        f.set("createdAt", receipt.createdAt)
        return SyncEnvelope(kind: .receipt, id: receipt.id, fields: f.fields)
    }

    static func envelope(_ item: InventoryItem) -> SyncEnvelope {
        var f = SyncFieldWriter()
        f.set("quantity", item.quantity)
        f.set("initialQuantity", item.initialQuantity)
        f.set("unit", item.unitRaw)
        f.set("purchaseDate", item.purchaseDate)
        f.set("expiryDate", item.expiryDate)
        f.set("expiryIsOverride", item.expiryIsOverride)
        f.set("openedDate", item.openedDate)
        f.set("quantityObservedAt", item.quantityObservedAt)
        f.set("status", item.statusRaw)
        f.set("notes", item.notes)
        f.set("createdAt", item.createdAt)
        f.set("updatedAt", item.updatedAt)
        return SyncEnvelope(kind: .item, id: item.id, fields: f.fields, refs: refs([
            "product": item.product.map { SyncRef(.product, $0.id) },
            "location": item.location.map { SyncRef(.location, $0.id) },
        ]))
    }

    static func envelope(_ purchase: PurchaseEvent) -> SyncEnvelope {
        var f = SyncFieldWriter()
        f.set("date", purchase.date)
        f.set("quantity", purchase.quantity)
        f.set("unit", purchase.unitRaw)
        f.set("priceCents", purchase.priceCents)
        f.set("currencyCode", purchase.currencyCode)
        f.set("source", purchase.sourceRaw)
        f.set("storeName", purchase.storeName)
        f.set("externalOrderID", purchase.externalOrderID)
        f.set("createdAt", purchase.createdAt)
        return SyncEnvelope(kind: .purchase, id: purchase.id, fields: f.fields, refs: refs([
            "product": purchase.product.map { SyncRef(.product, $0.id) },
            "receipt": purchase.receipt.map { SyncRef(.receipt, $0.id) },
        ]))
    }

    static func envelope(_ usage: UsageEvent) -> SyncEnvelope {
        var f = SyncFieldWriter()
        f.set("date", usage.date)
        f.set("quantity", usage.quantity)
        f.set("unit", usage.unitRaw)
        f.set("type", usage.typeRaw)
        f.set("createdAt", usage.createdAt)
        return SyncEnvelope(kind: .usage, id: usage.id, fields: f.fields, refs: refs([
            "product": usage.product.map { SyncRef(.product, $0.id) },
            "item": usage.item.map { SyncRef(.item, $0.id) },
        ]))
    }

    static func envelope(_ entry: ShoppingListItem) -> SyncEnvelope {
        var f = SyncFieldWriter()
        f.set("name", entry.name)
        f.set("quantity", entry.quantity)
        f.set("unit", entry.unitRaw)
        f.set("reason", entry.reasonRaw)
        f.set("note", entry.note)
        f.set("isChecked", entry.isChecked)
        f.set("addedAt", entry.addedAt)
        f.set("checkedAt", entry.checkedAt)
        return SyncEnvelope(kind: .shoppingItem, id: entry.id, fields: f.fields, refs: refs([
            "product": entry.product.map { SyncRef(.product, $0.id) },
        ]))
    }

    static func envelope(_ saved: SavedRecipe) -> SyncEnvelope {
        var f = SyncFieldWriter()
        f.set("title", saved.title)
        f.set("payload", saved.payload)
        f.set("isFavorite", saved.isFavorite)
        f.set("createdAt", saved.createdAt)
        f.set("lastCookedAt", saved.lastCookedAt)
        f.set("timesCooked", saved.timesCooked)
        return SyncEnvelope(kind: .savedRecipe, id: saved.id, fields: f.fields)
    }

    static func refs(_ pairs: [String: SyncRef?]) -> [String: SyncRef] {
        pairs.compactMapValues { $0 }
    }

    // MARK: - Shared → local

    /// Creates or updates the object a record describes. Fields the sender
    /// didn't know about are left as they are. Returns false when a
    /// reference points at something that hasn't arrived yet.
    @discardableResult
    func apply(_ envelope: SyncEnvelope) throws -> Bool {
        let r = SyncFieldReader(envelope.fields)
        var resolved = true
        /// Looks up a referenced object, noting when it's missing.
        func target<T>(_ key: String, _ lookup: (UUID) throws -> T?) rethrows -> T? {
            guard let ref = envelope.refs[key] else { return nil }
            let found = try lookup(ref.id)
            if found == nil { resolved = false }
            return found
        }

        switch envelope.kind {
        case .location:
            let object = try location(envelope.id) ?? adoptBuiltInLocation(envelope) ?? insert(StorageLocation(
                name: "", kind: .custom, climate: .room, systemImage: "shippingbox", sortOrder: 0, isBuiltIn: false
            ), id: envelope.id)
            if let v = r.string("name") { object.name = v }
            if let v = r.string("kind") { object.kindRaw = v }
            if let v = r.string("climate") { object.climateRaw = v }
            if let v = r.string("systemImage") { object.systemImage = v }
            if let v = r.int("sortOrder") { object.sortOrder = v }
            if let v = r.bool("isBuiltIn") { object.isBuiltIn = v }
            if let v = r.date("createdAt") { object.createdAt = v }

        case .product:
            let object = try product(envelope.id) ?? adoptProduct(envelope) ?? insert(Product(name: "", category: .other), id: envelope.id)
            if let v = r.string("name") { object.name = v }
            if r.has("brand") { object.brand = r.string("brand") }
            if let v = r.string("category") { object.categoryRaw = v }
            if let v = r.string("defaultUnit") { object.defaultUnitRaw = v }
            if r.has("packageSizeText") { object.packageSizeText = r.string("packageSizeText") }
            if r.has("imageURL") { object.imageURLString = r.string("imageURL") }
            if r.has("shelfLifeRoomDays") { object.shelfLifeRoomDays = r.int("shelfLifeRoomDays") }
            if r.has("shelfLifeFridgeDays") { object.shelfLifeFridgeDays = r.int("shelfLifeFridgeDays") }
            if r.has("shelfLifeFreezerDays") { object.shelfLifeFreezerDays = r.int("shelfLifeFreezerDays") }
            if let v = r.bool("isIngredient") { object.isIngredient = v }
            if let v = r.bool("tracksRunOut") { object.tracksRunOut = v }
            if let v = r.bool("tracksExpiry") { object.tracksExpiry = v }
            if let v = r.date("createdAt") { object.createdAt = v }
            if let v = r.date("updatedAt") { object.updatedAt = v }

        case .alias:
            let object = try alias(envelope.id) ?? insert(ProductAlias(kind: .barcode, value: ""), id: envelope.id)
            if let v = r.string("kind") { object.kindRaw = v }
            if let v = r.string("value") { object.value = v }
            if let v = r.date("createdAt") { object.createdAt = v }
            if let v = r.date("lastUsedAt") { object.lastUsedAt = v }
            object.product = try target("product", product)

        case .receipt:
            let object = try receipt(envelope.id) ?? insert(Receipt(
                storeName: nil, purchaseDate: Date(), totalCents: nil, currencyCode: "USD", rawText: ""
            ), id: envelope.id)
            if r.has("storeName") { object.storeName = r.string("storeName") }
            if let v = r.date("purchaseDate") { object.purchaseDate = v }
            if r.has("totalCents") { object.totalCents = r.int("totalCents") }
            if let v = r.string("currencyCode") { object.currencyCode = v }
            if let v = r.string("rawText") { object.rawText = v }
            if let v = r.date("createdAt") { object.createdAt = v }

        case .item:
            let object = try item(envelope.id) ?? insert(InventoryItem(quantity: 0, unit: .each, purchaseDate: Date()), id: envelope.id)
            if let v = r.double("quantity") { object.quantity = v }
            if let v = r.double("initialQuantity") { object.initialQuantity = v }
            if let v = r.string("unit") { object.unitRaw = v }
            if let v = r.date("purchaseDate") { object.purchaseDate = v }
            if r.has("expiryDate") { object.expiryDate = r.date("expiryDate") }
            if let v = r.bool("expiryIsOverride") { object.expiryIsOverride = v }
            if r.has("openedDate") { object.openedDate = r.date("openedDate") }
            if r.has("quantityObservedAt") { object.quantityObservedAt = r.date("quantityObservedAt") }
            if let v = r.string("status") { object.statusRaw = v }
            if let v = r.string("notes") { object.notes = v }
            if let v = r.date("createdAt") { object.createdAt = v }
            if let v = r.date("updatedAt") { object.updatedAt = v }
            object.product = try target("product", product)
            object.location = try target("location", location)

        case .purchase:
            let object = try purchase(envelope.id) ?? insert(PurchaseEvent(date: Date(), quantity: 0, unit: .each, source: .manual), id: envelope.id)
            if let v = r.date("date") { object.date = v }
            if let v = r.double("quantity") { object.quantity = v }
            if let v = r.string("unit") { object.unitRaw = v }
            if r.has("priceCents") { object.priceCents = r.int("priceCents") }
            if let v = r.string("currencyCode") { object.currencyCode = v }
            if let v = r.string("source") { object.sourceRaw = v }
            if r.has("storeName") { object.storeName = r.string("storeName") }
            if r.has("externalOrderID") { object.externalOrderID = r.string("externalOrderID") }
            if let v = r.date("createdAt") { object.createdAt = v }
            object.product = try target("product", product)
            object.receipt = try target("receipt", receipt)

        case .usage:
            let object = try usage(envelope.id) ?? insert(UsageEvent(date: Date(), quantity: 0, unit: .each, type: .partiallyUsed), id: envelope.id)
            if let v = r.date("date") { object.date = v }
            if let v = r.double("quantity") { object.quantity = v }
            if let v = r.string("unit") { object.unitRaw = v }
            if let v = r.string("type") { object.typeRaw = v }
            if let v = r.date("createdAt") { object.createdAt = v }
            object.product = try target("product", product)
            object.item = try target("item", item)

        case .shoppingItem:
            let object = try shoppingItem(envelope.id) ?? insert(ShoppingListItem(name: "", quantity: 1, unit: .each, reason: .manual), id: envelope.id)
            if let v = r.string("name") { object.name = v }
            if let v = r.double("quantity") { object.quantity = v }
            if let v = r.string("unit") { object.unitRaw = v }
            if let v = r.string("reason") { object.reasonRaw = v }
            if r.has("note") { object.note = r.string("note") }
            if let v = r.bool("isChecked") { object.isChecked = v }
            if let v = r.date("addedAt") { object.addedAt = v }
            if r.has("checkedAt") { object.checkedAt = r.date("checkedAt") }
            object.product = try target("product", product)

        case .savedRecipe:
            let object = try savedRecipe(envelope.id) ?? insert(SavedRecipe(id: envelope.id), id: envelope.id)
            if let v = r.string("title") { object.title = v }
            if let v = r.data("payload") { object.payload = v }
            if let v = r.bool("isFavorite") { object.isFavorite = v }
            if let v = r.date("createdAt") { object.createdAt = v }
            if r.has("lastCookedAt") { object.lastCookedAt = r.date("lastCookedAt") }
            if let v = r.int("timesCooked") { object.timesCooked = v }
        }
        return resolved
    }

    /// Deletes the object a record described, if it's still here.
    func delete(kind: SyncKind, id: UUID) throws {
        let object: (any PersistentModel)?
        switch kind {
        case .location: object = try location(id)
        case .product: object = try product(id)
        case .alias: object = try alias(id)
        case .receipt: object = try receipt(id)
        case .item: object = try item(id)
        case .purchase: object = try purchase(id)
        case .usage: object = try usage(id)
        case .shoppingItem: object = try shoppingItem(id)
        case .savedRecipe: object = try savedRecipe(id)
        }
        if let object { context.delete(object) }
    }

    // MARK: - Merging duplicates

    /// Both phones start with the same built-in locations under different
    /// IDs. The incoming one takes over the local one (and its items), so
    /// joining a home doesn't leave two "Fridge"s. Only locations never
    /// shared before are taken over.
    private func adoptBuiltInLocation(_ envelope: SyncEnvelope) throws -> StorageLocation? {
        let r = SyncFieldReader(envelope.fields)
        guard r.bool("isBuiltIn") == true, let kind = r.string("kind") else { return nil }
        let candidate = try context.fetch(FetchDescriptor<StorageLocation>())
            .first { $0.isBuiltIn && $0.kindRaw == kind }
        guard let candidate, try !wasShared(.location, candidate.id) else { return nil }
        candidate.id = envelope.id
        return candidate
    }

    /// A product with the same name and brand that this phone added before
    /// joining becomes the shared one, so its history merges.
    private func adoptProduct(_ envelope: SyncEnvelope) throws -> Product? {
        let r = SyncFieldReader(envelope.fields)
        guard let name = r.string("name") else { return nil }
        let nameKey = TextNormalizer.key(name)
        let brandKey = TextNormalizer.key(r.string("brand") ?? "")
        guard !nameKey.isEmpty else { return nil }
        let candidate = try context.fetch(FetchDescriptor<Product>()).first {
            TextNormalizer.key($0.name) == nameKey && TextNormalizer.key($0.brand ?? "") == brandKey
        }
        guard let candidate, try !wasShared(.product, candidate.id) else { return nil }
        candidate.id = envelope.id
        return candidate
    }

    /// Whether iCloud has ever confirmed this record.
    private func wasShared(_ kind: SyncKind, _ id: UUID) throws -> Bool {
        let name = SyncRecordName.make(kind, id)
        var descriptor = FetchDescriptor<SyncRecordState>(predicate: #Predicate<SyncRecordState> { state in state.recordName == name })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.payload != nil
    }

    // MARK: - Lookups

    private func insert<T: PersistentModel & SyncIdentifiable>(_ object: T, id: UUID) -> T {
        object.setSyncID(id)
        context.insert(object)
        return object
    }

    func location(_ id: UUID) throws -> StorageLocation? {
        var descriptor = FetchDescriptor<StorageLocation>(predicate: #Predicate<StorageLocation> { object in object.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func product(_ id: UUID) throws -> Product? {
        var descriptor = FetchDescriptor<Product>(predicate: #Predicate<Product> { object in object.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func alias(_ id: UUID) throws -> ProductAlias? {
        var descriptor = FetchDescriptor<ProductAlias>(predicate: #Predicate<ProductAlias> { object in object.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func receipt(_ id: UUID) throws -> Receipt? {
        var descriptor = FetchDescriptor<Receipt>(predicate: #Predicate<Receipt> { object in object.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func item(_ id: UUID) throws -> InventoryItem? {
        var descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate<InventoryItem> { object in object.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func purchase(_ id: UUID) throws -> PurchaseEvent? {
        var descriptor = FetchDescriptor<PurchaseEvent>(predicate: #Predicate<PurchaseEvent> { object in object.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func usage(_ id: UUID) throws -> UsageEvent? {
        var descriptor = FetchDescriptor<UsageEvent>(predicate: #Predicate<UsageEvent> { object in object.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func shoppingItem(_ id: UUID) throws -> ShoppingListItem? {
        var descriptor = FetchDescriptor<ShoppingListItem>(predicate: #Predicate<ShoppingListItem> { object in object.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func savedRecipe(_ id: UUID) throws -> SavedRecipe? {
        var descriptor = FetchDescriptor<SavedRecipe>(predicate: #Predicate<SavedRecipe> { object in object.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

/// Models whose ID the sync layer sets when it creates them from a record.
protocol SyncIdentifiable: AnyObject {
    func setSyncID(_ id: UUID)
}

extension StorageLocation: SyncIdentifiable { func setSyncID(_ id: UUID) { self.id = id } }
extension Product: SyncIdentifiable { func setSyncID(_ id: UUID) { self.id = id } }
extension ProductAlias: SyncIdentifiable { func setSyncID(_ id: UUID) { self.id = id } }
extension Receipt: SyncIdentifiable { func setSyncID(_ id: UUID) { self.id = id } }
extension InventoryItem: SyncIdentifiable { func setSyncID(_ id: UUID) { self.id = id } }
extension PurchaseEvent: SyncIdentifiable { func setSyncID(_ id: UUID) { self.id = id } }
extension UsageEvent: SyncIdentifiable { func setSyncID(_ id: UUID) { self.id = id } }
extension ShoppingListItem: SyncIdentifiable { func setSyncID(_ id: UUID) { self.id = id } }
extension SavedRecipe: SyncIdentifiable { func setSyncID(_ id: UUID) { self.id = id } }
