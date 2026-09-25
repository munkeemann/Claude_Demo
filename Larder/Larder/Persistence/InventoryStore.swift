import Foundation
import InventoryCore
import SwiftData

enum InventoryStoreError: LocalizedError {
    case invalidDraft([ItemDraft.Issue])
    case cannotDeleteBuiltInLocation

    var errorDescription: String? {
        switch self {
        case .invalidDraft(let issues): issues.map(\.message).joined(separator: " ")
        case .cannotDeleteBuiltInLocation: "Built-in locations can't be deleted."
        }
    }
}

/// All inventory writes go through here so views stay thin and the rules
/// (product de-duplication, purchase/usage logging, status updates) are tested
/// in one place. Create one per use; it only wraps a `ModelContext`.
@MainActor
struct InventoryStore {
    let context: ModelContext
    var now: () -> Date = Date.init

    init(context: ModelContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    // MARK: - Locations

    func locations() throws -> [StorageLocation] {
        try context.fetch(FetchDescriptor<StorageLocation>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    /// Inserts any missing built-in locations. Safe to call on every launch.
    func seedLocationsIfNeeded() throws {
        let existingKinds = Set(try locations().filter(\.isBuiltIn).map(\.kind))
        for (index, kind) in LocationKind.builtIn.enumerated() where !existingKinds.contains(kind) {
            context.insert(StorageLocation(builtIn: kind, sortOrder: index))
        }
        if context.hasChanges { try context.save() }
    }

    func location(id: UUID?) throws -> StorageLocation? {
        guard let id else { return nil }
        return try locations().first { $0.id == id }
    }

    /// The built-in location a category is normally stored in.
    func defaultLocation(for category: ProductCategory) throws -> StorageLocation? {
        let kind = category.defaultLocationKind
        let all = try locations()
        return all.first { $0.isBuiltIn && $0.kind == kind } ?? all.first
    }

    @discardableResult
    func addLocation(name: String, climate: StorageClimate, systemImage: String) throws -> StorageLocation {
        let nextOrder = (try locations().map(\.sortOrder).max() ?? -1) + 1
        let location = StorageLocation(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .custom,
            climate: climate,
            systemImage: systemImage,
            sortOrder: nextOrder,
            isBuiltIn: false,
            now: now()
        )
        context.insert(location)
        try context.save()
        return location
    }

    /// Deletes a custom location. Its items stay in the inventory, unassigned.
    func deleteLocation(_ location: StorageLocation) throws {
        guard !location.isBuiltIn else { throw InventoryStoreError.cannotDeleteBuiltInLocation }
        context.delete(location)
        try context.save()
    }

    /// Persists a new order after the user drags locations around.
    func reorderLocations(_ ordered: [StorageLocation]) throws {
        for (index, location) in ordered.enumerated() where location.sortOrder != index {
            location.sortOrder = index
        }
        try context.save()
    }

    // MARK: - Products

    func product(forBarcode code: String) throws -> Product? {
        let key = TextNormalizer.barcode(code)
        guard !key.isEmpty else { return nil }
        return try alias(kind: .barcode, value: key)?.product
    }

    func alias(kind: AliasKind, value: String) throws -> ProductAlias? {
        let kindRaw = kind.rawValue
        var descriptor = FetchDescriptor<ProductAlias>(
            predicate: #Predicate<ProductAlias> { alias in alias.kindRaw == kindRaw && alias.value == value }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Case-, punctuation- and diacritic-insensitive match on name + brand.
    func product(named name: String, brand: String?) throws -> Product? {
        let nameKey = TextNormalizer.key(name)
        let brandKey = TextNormalizer.key(brand ?? "")
        guard !nameKey.isEmpty else { return nil }
        return try context.fetch(FetchDescriptor<Product>()).first {
            TextNormalizer.key($0.name) == nameKey && TextNormalizer.key($0.brand ?? "") == brandKey
        }
    }

    /// Reuses an existing product (by barcode, then by name + brand) or creates one.
    func findOrCreateProduct(for draft: ItemDraft) throws -> Product {
        if let barcode = draft.barcode, let existing = try product(forBarcode: barcode) {
            return existing
        }
        if let existing = try product(named: draft.trimmedName, brand: draft.trimmedBrand) {
            try attachBarcode(draft.barcode, to: existing)
            return existing
        }
        let product = Product(name: draft.trimmedName, brand: draft.trimmedBrand, category: draft.category, now: now())
        context.insert(product)
        try attachBarcode(draft.barcode, to: product)
        return product
    }

    func attachBarcode(_ code: String?, to product: Product) throws {
        guard let code else { return }
        try attachAlias(kind: .barcode, value: TextNormalizer.barcode(code), to: product)
    }

    /// Points an alias at `product`, creating it if needed. Re-pointing an
    /// existing alias is how corrections replace earlier mappings.
    func attachAlias(kind: AliasKind, value: String, to product: Product) throws {
        guard !value.isEmpty else { return }
        if let existing = try alias(kind: kind, value: value) {
            existing.product = product
            existing.lastUsedAt = now()
            return
        }
        let alias = ProductAlias(kind: kind, value: value, now: now())
        context.insert(alias)
        alias.product = product
    }

    func product(id: UUID) throws -> Product? {
        var descriptor = FetchDescriptor<Product>(predicate: #Predicate<Product> { product in product.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func applyProductFields(from draft: ItemDraft, to product: Product) {
        product.name = draft.trimmedName
        product.brand = draft.trimmedBrand
        product.category = draft.category
        product.defaultUnit = draft.unit
        product.isIngredient = draft.isIngredient
        product.tracksRunOut = draft.tracksRunOut
        product.tracksExpiry = draft.tracksExpiry
        if let size = draft.packageSizeText, !size.isEmpty { product.packageSizeText = size }
        if let url = draft.imageURL { product.imageURL = url }
        product.updatedAt = now()
    }

    // MARK: - Items

    /// Adds a stocked item and logs the purchase.
    @discardableResult
    func addItem(from draft: ItemDraft, source: PurchaseSource) throws -> InventoryItem {
        guard draft.isValid else { throw InventoryStoreError.invalidDraft(draft.issues) }
        let product = try findOrCreateProduct(for: draft)
        applyProductFields(from: draft, to: product)
        let item = try insertStock(from: draft, product: product, source: source)
        try context.save()
        return item
    }

    /// Inserts an item plus, unless `logsPurchase` is false (stock that was
    /// already in the house), its purchase event. Does not save.
    private func insertStock(
        from draft: ItemDraft,
        product: Product,
        source: PurchaseSource,
        storeName: String? = nil,
        receipt: Receipt? = nil,
        currencyCode: String? = nil,
        logsPurchase: Bool = true
    ) throws -> InventoryItem {
        let item = InventoryItem(
            quantity: draft.quantity,
            unit: draft.unit,
            purchaseDate: draft.purchaseDate,
            expiryDate: draft.expiryDate,
            expiryIsOverride: draft.expiryDate != nil && !draft.expiryIsEstimate,
            notes: draft.notes,
            now: now()
        )
        context.insert(item)
        item.product = product
        item.location = try location(id: draft.locationID)

        // Remember a suggested shelf life for this climate unless one is set.
        if let days = draft.estimatedShelfLifeDays, let climate = item.location?.climate {
            switch climate {
            case .room where product.shelfLifeRoomDays == nil: product.shelfLifeRoomDays = days
            case .fridge where product.shelfLifeFridgeDays == nil: product.shelfLifeFridgeDays = days
            case .freezer where product.shelfLifeFreezerDays == nil: product.shelfLifeFreezerDays = days
            default: break
            }
        }
        if item.expiryDate == nil {
            applyEstimatedExpiry(to: item)
        }

        guard logsPurchase else { return item }
        let purchase = PurchaseEvent(
            date: draft.purchaseDate,
            quantity: draft.quantity,
            unit: draft.unit,
            source: source,
            priceCents: draft.priceCents,
            currencyCode: currencyCode ?? Locale.current.currency?.identifier ?? "USD",
            storeName: storeName,
            now: now()
        )
        context.insert(purchase)
        purchase.product = product
        purchase.receipt = receipt
        return item
    }

    // MARK: - Receipts

    /// Every remembered receipt-text → product mapping.
    func receiptHints() throws -> [ReceiptHint] {
        let kindRaw = AliasKind.receiptText.rawValue
        let aliases = try context.fetch(
            FetchDescriptor<ProductAlias>(predicate: #Predicate<ProductAlias> { alias in alias.kindRaw == kindRaw })
        )
        return aliases.compactMap { alias -> ReceiptHint? in
            guard let product = alias.product else { return nil }
            return ReceiptHint(
                key: alias.value,
                productID: product.id,
                name: product.name,
                brand: product.brand,
                category: product.category,
                unit: product.defaultUnit
            )
        }
    }

    /// Adds every included line as stock, logs purchases against a `Receipt`,
    /// and remembers each line's text → product mapping so the same receipt
    /// text resolves the same way next time (including any corrections).
    @discardableResult
    func importReceipt(_ review: ReceiptReview) throws -> [InventoryItem] {
        let lines = review.includedLines
        guard !lines.isEmpty else { return [] }
        let invalid = lines.filter { !$0.isValid }
        guard invalid.isEmpty else { throw InventoryStoreError.invalidDraft([.missingName]) }

        let storeName = review.storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let receipt = Receipt(
            storeName: storeName.isEmpty ? nil : storeName,
            purchaseDate: review.purchaseDate,
            totalCents: review.totalCents,
            currencyCode: review.currencyCode,
            rawText: review.rawText,
            now: now()
        )
        context.insert(receipt)

        var items: [InventoryItem] = []
        for line in lines {
            let draft = line.draft(purchaseDate: review.purchaseDate)
            let product: Product
            if let id = line.matchedProductID, !line.wasCorrected, let matched = try self.product(id: id) {
                product = matched
            } else if let existing = try self.product(named: draft.trimmedName, brand: draft.trimmedBrand) {
                product = existing
            } else {
                product = Product(name: draft.trimmedName, brand: draft.trimmedBrand, category: draft.category, now: now())
                context.insert(product)
                applyProductFields(from: draft, to: product)
            }
            if product.packageSizeText == nil, let size = draft.packageSizeText {
                product.packageSizeText = size
            }
            try attachAlias(kind: .receiptText, value: line.aliasKey, to: product)
            items.append(try insertStock(
                from: draft,
                product: product,
                source: .receipt,
                storeName: receipt.storeName,
                receipt: receipt,
                currencyCode: review.currencyCode
            ))
        }
        try context.save()
        return items
    }

    // MARK: - Shelf scans

    /// In-stock items at a location, with short references for Claude.
    func shelfScanHints(locationID: UUID?) throws -> [ShelfScanHint] {
        let items = try context.fetch(FetchDescriptor<InventoryItem>())
            .filter { $0.status.isActive && $0.location?.id == locationID }
            .sorted { ($0.displayName, $0.purchaseDate) < ($1.displayName, $1.purchaseDate) }
        return ShelfScanPrompt.hints(for: items.map { item in
            (id: item.id, name: item.displayName, brand: item.product?.brand, quantity: item.quantity, initialQuantity: item.initialQuantity, unit: item.unit)
        })
    }

    /// Applies a reviewed shelf scan:
    /// - New products are added as stock. Only when the user says they were
    ///   just bought is a purchase logged; otherwise they were already in
    ///   the house and logging one would skew usage estimates.
    /// - Tracked items get their new count, which pins the forecast's
    ///   projection. A count that went up after shopping logs the increase
    ///   as a purchase.
    /// - Unseen items the user marked finished are closed.
    func importShelfScan(_ review: ShelfScanReview) throws {
        let lines = review.includedLines
        guard lines.allSatisfy(\.isValid) else { throw InventoryStoreError.invalidDraft([.missingName]) }
        let today = now()

        for line in lines {
            switch line.action {
            case .add:
                let draft = line.draft(locationID: review.locationID, date: today)
                let product = try findOrCreateProduct(for: draft)
                applyProductFields(from: draft, to: product)
                let item = try insertStock(from: draft, product: product, source: .shelfScan, logsPurchase: review.justBought)
                if let full = line.fullQuantity, full > line.quantity {
                    item.initialQuantity = full
                    item.status = QuickActionCalculator.status(forQuantity: line.quantity, initialQuantity: full)
                }
            case .update:
                guard let id = line.matchedItemID, let item = try self.item(id: id) else { continue }
                if review.justBought, line.increase > 0 {
                    let purchase = PurchaseEvent(date: today, quantity: line.increase, unit: item.unit, source: .shelfScan, now: today)
                    context.insert(purchase)
                    purchase.product = item.product
                }
                setCount(item, to: line.quantity)
            }
        }
        for unseen in review.unseen where unseen.markFinished {
            if let item = try self.item(id: unseen.hint.itemID), item.status.isActive {
                setCount(item, to: 0)
            }
        }
        try context.save()
    }

    /// Applies edits from the item form. Quantity edits are corrections, so
    /// they don't log usage.
    func update(_ item: InventoryItem, from draft: ItemDraft) throws {
        guard draft.isValid else { throw InventoryStoreError.invalidDraft(draft.issues) }
        if let product = item.product {
            applyProductFields(from: draft, to: product)
            try attachBarcode(draft.barcode, to: product)
        }
        let expiryEdited = draft.expiryDate != item.expiryDate
        if expiryEdited {
            item.expiryIsOverride = draft.expiryDate != nil
        }
        item.expiryDate = draft.expiryDate
        if draft.quantity != item.quantity || draft.unit != item.unit {
            item.quantityObservedAt = now()
        }
        if draft.unit != item.unit || draft.quantity > item.initialQuantity {
            item.initialQuantity = draft.quantity
        }
        item.quantity = draft.quantity
        item.unit = draft.unit
        item.status = QuickActionCalculator.status(forQuantity: draft.quantity, initialQuantity: item.initialQuantity)
        item.purchaseDate = draft.purchaseDate
        item.notes = draft.notes
        let previousClimate = item.location?.climate
        item.location = try location(id: draft.locationID)
        // Moving an item to a colder or warmer place changes its estimate.
        if !expiryEdited && !item.expiryIsOverride && item.location?.climate != previousClimate {
            item.expiryDate = nil
            applyEstimatedExpiry(to: item)
        }
        item.updatedAt = now()
        try context.save()
    }

    // MARK: - Expiry estimates

    /// Sets an estimated expiry from the product's shelf life (for the item's
    /// climate) or the category table. User-set dates are never touched.
    func applyEstimatedExpiry(to item: InventoryItem) {
        guard !item.expiryIsOverride, let product = item.product, product.tracksExpiry else { return }
        let climate = item.location?.climate ?? product.category.defaultClimate
        let estimate = ExpiryEstimator.estimate(
            purchaseDate: item.purchaseDate,
            category: product.category,
            climate: climate,
            productShelfLifeDays: product.shelfLifeDays(for: climate)
        )
        item.expiryDate = estimate?.date
    }

    /// Fills in estimates for in-stock items that have none. Safe to call
    /// on every launch.
    func refreshEstimatedExpiries() throws {
        let items = try context.fetch(FetchDescriptor<InventoryItem>())
        for item in items where item.expiryDate == nil && item.status.isActive {
            applyEstimatedExpiry(to: item)
        }
        if context.hasChanges { try context.save() }
    }

    /// Removes an item entered by mistake. Purchase and usage history stays
    /// with the product.
    func delete(_ item: InventoryItem) throws {
        context.delete(item)
        try context.save()
    }

    /// Applies a quick action and logs the matching usage event.
    @discardableResult
    func apply(_ action: QuickAction, to item: InventoryItem) throws -> QuickActionResult {
        let result = QuickActionCalculator.apply(action, to: item.state)
        item.quantity = result.quantity
        item.status = result.status
        item.quantityObservedAt = now()
        item.updatedAt = now()

        if result.usageQuantity > 0 || result.usageType != .partiallyUsed {
            let usage = UsageEvent(
                date: now(),
                quantity: result.usageQuantity,
                unit: item.unit,
                type: result.usageType,
                now: now()
            )
            context.insert(usage)
            usage.product = item.product
            usage.item = item
        }
        try context.save()
        return result
    }

    /// Confirms an item the forecast projects as finished. No usage event is
    /// logged: the item ran out some time ago, not now, and purchases already
    /// carry the rate.
    func confirmFinished(_ item: InventoryItem) throws {
        setCount(item, to: 0)
        try context.save()
    }

    /// Records how much is actually left (from a shelf scan or "Still have
    /// some"). Like an edit, it's a correction, so no usage is logged, but it
    /// pins the forecast's projection for this item to now.
    func recount(_ item: InventoryItem, quantity: Double) throws {
        setCount(item, to: quantity)
        try context.save()
    }

    /// Sets a counted amount without saving. Zero means used up.
    private func setCount(_ item: InventoryItem, to quantity: Double) {
        let counted = max(0, quantity)
        item.quantity = counted
        if counted > item.initialQuantity { item.initialQuantity = counted }
        item.status = QuickActionCalculator.status(forQuantity: counted, initialQuantity: item.initialQuantity)
        item.quantityObservedAt = now()
        item.updatedAt = now()
    }

    // MARK: - Shopping list

    func shoppingItems() throws -> [ShoppingListItem] {
        try context.fetch(FetchDescriptor<ShoppingListItem>(sortBy: [SortDescriptor(\.addedAt)]))
    }

    /// Adds an entry unless an unchecked one for the same product (or the
    /// same name, for free-text entries) is already on the list.
    @discardableResult
    func addToShoppingList(
        name: String,
        quantity: Double = 1,
        unit: MeasureUnit = .each,
        reason: ShoppingReason = .manual,
        product: Product? = nil,
        note: String? = nil
    ) throws -> ShoppingListItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = TextNormalizer.key(trimmed)
        let open = try shoppingItems().filter { !$0.isChecked }
        if let existing = open.first(where: { entry in
            if let product, entry.product?.id == product.id { return true }
            return TextNormalizer.key(entry.name) == key
        }) {
            return existing
        }
        let entry = ShoppingListItem(name: trimmed, quantity: quantity, unit: unit, reason: reason, note: note, now: now())
        context.insert(entry)
        entry.product = product
        try context.save()
        return entry
    }

    /// Adds predicted run-outs to the list.
    func addSuggestions(_ suggestions: [ShoppingSuggestion]) throws {
        for suggestion in suggestions {
            try addToShoppingList(
                name: suggestion.name,
                quantity: suggestion.quantity,
                unit: suggestion.unit,
                reason: .predicted,
                product: try product(id: suggestion.productID)
            )
        }
    }

    func setChecked(_ entry: ShoppingListItem, _ isChecked: Bool) throws {
        entry.isChecked = isChecked
        entry.checkedAt = isChecked ? now() : nil
        try context.save()
    }

    func deleteShoppingItem(_ entry: ShoppingListItem) throws {
        context.delete(entry)
        try context.save()
    }

    func clearCheckedShoppingItems() throws {
        for entry in try shoppingItems() where entry.isChecked {
            context.delete(entry)
        }
        try context.save()
    }

    // MARK: - Data management

    /// Loads `SampleData`, skipping products that already exist by name.
    func loadSampleData() throws {
        try seedLocationsIfNeeded()
        let today = now()
        let calendar = Calendar.current
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: today) ?? today
        }
        let locationsByKind = Dictionary(
            try locations().filter(\.isBuiltIn).map { ($0.kind, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for sample in SampleData.products {
            if try product(named: sample.name, brand: sample.brand) != nil { continue }
            let product = Product(name: sample.name, brand: sample.brand, category: sample.category, now: today)
            product.defaultUnit = sample.unit
            product.packageSizeText = sample.packageSizeText
            context.insert(product)
            try attachBarcode(sample.barcode, to: product)

            for purchase in sample.purchases {
                let event = PurchaseEvent(
                    date: daysAgo(purchase.daysAgo),
                    quantity: purchase.quantity,
                    unit: sample.unit,
                    source: .receipt,
                    priceCents: purchase.priceCents,
                    currencyCode: "USD",
                    storeName: purchase.store,
                    now: today
                )
                context.insert(event)
                event.product = product
            }
            for usage in sample.usages {
                let event = UsageEvent(date: daysAgo(usage.daysAgo), quantity: usage.quantity, unit: sample.unit, type: usage.type, now: today)
                context.insert(event)
                event.product = product
            }
            if let stock = sample.stock {
                let item = InventoryItem(
                    quantity: stock.quantity,
                    unit: sample.unit,
                    purchaseDate: daysAgo(stock.purchasedDaysAgo),
                    expiryDate: stock.expiresInDays.flatMap { calendar.date(byAdding: .day, value: $0, to: today) },
                    now: daysAgo(stock.purchasedDaysAgo)
                )
                item.initialQuantity = stock.initialQuantity
                item.status = QuickActionCalculator.status(forQuantity: stock.quantity, initialQuantity: stock.initialQuantity)
                if stock.quantity < stock.initialQuantity {
                    item.quantityObservedAt = today
                }
                context.insert(item)
                item.product = product
                item.location = locationsByKind[sample.location]
            }
        }
        try context.save()
    }

    /// Deletes every product, item and event. Locations are kept.
    func deleteAllData() throws {
        for product in try context.fetch(FetchDescriptor<Product>()) {
            context.delete(product)
        }
        // Orphans (e.g. items whose product was never set) are removed too.
        for item in try context.fetch(FetchDescriptor<InventoryItem>()) {
            context.delete(item)
        }
        for event in try context.fetch(FetchDescriptor<PurchaseEvent>()) {
            context.delete(event)
        }
        for event in try context.fetch(FetchDescriptor<UsageEvent>()) {
            context.delete(event)
        }
        for alias in try context.fetch(FetchDescriptor<ProductAlias>()) {
            context.delete(alias)
        }
        for receipt in try context.fetch(FetchDescriptor<Receipt>()) {
            context.delete(receipt)
        }
        for entry in try context.fetch(FetchDescriptor<ShoppingListItem>()) {
            context.delete(entry)
        }
        for saved in try context.fetch(FetchDescriptor<SavedRecipe>()) {
            context.delete(saved)
        }
        try context.save()
    }
}
