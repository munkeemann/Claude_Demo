import InventoryCore
import SwiftData
import SwiftUI

struct ItemDetailView: View {
    let item: InventoryItem

    @Environment(\.modelContext) private var modelContext
    @State private var editor: EditorSheet?
    @State private var isUsingSome = false
    @State private var isRecounting = false
    @State private var addedToList = false
    @State private var isCapturingDate = false
    @State private var isPickingGuide = false
    @State private var pendingMove: StorageLocation?
    @State private var errorMessage: String?
    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]

    var body: some View {
        let forecast = item.product.flatMap { product in
            product.tracksRunOut ? RunOutForecaster.forecast(product.consumptionHistory, now: Date()) : nil
        }
        let estimate = forecast?.items.first { $0.id == item.id }
        List {
            Section {
                HStack(spacing: 14) {
                    CategoryIcon(category: item.product?.category ?? .other, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .font(.title3.weight(.semibold))
                        if let brand = item.product?.brand {
                            Text(brand)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    StatusBadge(status: item.status)
                }
                .padding(.vertical, 4)
            }

            Section("Details") {
                LabeledContent("Quantity", value: quantityText)
                LabeledContent("Location", value: item.location?.name ?? "None")
                LabeledContent("Category", value: item.product?.category.displayName ?? "Other")
                LabeledContent("Purchased", value: item.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                if let opened = item.openedDate {
                    LabeledContent("Opened", value: opened.formatted(date: .abbreviated, time: .omitted))
                }
                if let thawed = item.thawedDate, item.location?.climate != .freezer {
                    LabeledContent("Out of the freezer", value: thawed.formatted(date: .abbreviated, time: .omitted))
                }
                if let size = item.product?.packageSizeText {
                    LabeledContent("Package size", value: size)
                }
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .foregroundStyle(.secondary)
                }
            }

            ExpirySection(
                item: item,
                result: item.expiryIsOverride ? nil : store.expiryResult(for: item),
                onCaptureDate: { isCapturingDate = true },
                onClearDate: { perform { try store.setPackageDate(item, nil) } },
                onPickGuide: { isPickingGuide = true },
                strictness: store.expiryStrictness()
            )

            if let forecast {
                UsageSection(
                    item: item,
                    forecast: forecast,
                    estimate: item.status.isActive ? estimate : nil,
                    onFinished: { perform { try InventoryStore(context: modelContext).confirmFinished(item) } },
                    onRecount: { isRecounting = true }
                )
            }

            if item.status.isActive {
                Section("Quick actions") {
                    Button { isUsingSome = true } label: {
                        Label("Used some…", systemImage: "minus.circle")
                    }
                    Button { isRecounting = true } label: {
                        Label("How much is left?", systemImage: "gauge.with.dots.needle.50percent")
                    }
                    Button { apply(.usedUp) } label: {
                        Label("Used it all", systemImage: "checkmark.circle")
                    }
                    Button { apply(.tossed) } label: {
                        Label("Tossed it", systemImage: "xmark.bin")
                    }
                    .tint(Theme.terracotta)
                }

                Section("Storage") {
                    if item.location?.climate != .freezer {
                        Button { perform { try store.freeze(item) } } label: {
                            Label("Freeze it", systemImage: "snowflake")
                        }
                        if item.product?.foodKeeper?.freezingNotRecommended == true {
                            Text("USDA doesn't recommend freezing this; it may lose quality.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Menu {
                        ForEach(locations.filter { $0.id != item.location?.id }) { location in
                            Button { move(to: location) } label: {
                                Label(location.name, systemImage: location.systemImage)
                            }
                        }
                    } label: {
                        Label("Move to…", systemImage: "arrow.right.circle")
                    }
                    Button {
                        perform { try store.setOpened(item, item.openedDate == nil ? Date() : nil) }
                    } label: {
                        Label(item.openedDate == nil ? "Mark as opened" : "Mark as sealed", systemImage: item.openedDate == nil ? "seal" : "seal.fill")
                    }
                }
            }

            Section {
                Button { editor = .add(item.restockDraft()) } label: {
                    Label("Buy again", systemImage: "arrow.clockwise")
                }
                Button { addToShoppingList() } label: {
                    Label(addedToList ? "On shopping list" : "Add to shopping list", systemImage: addedToList ? "checkmark" : "cart.badge.plus")
                }
                .disabled(addedToList)
            }

            if !history.isEmpty {
                Section("History") {
                    ForEach(history) { entry in
                        HistoryRow(entry: entry)
                    }
                }
            }
        }
        .themedBackground()
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { editor = .edit(item) }
        }
        .sheet(item: $editor) { sheet in
            NavigationStack {
                ItemEditorView(mode: sheet.mode)
            }
        }
        .sheet(isPresented: $isUsingSome) {
            UseSomeSheet(item: item)
        }
        .sheet(isPresented: $isRecounting) {
            RecountSheet(item: item, suggested: estimate.map(\.roundedRemaining))
        }
        .sheet(isPresented: $isCapturingDate) {
            NavigationStack {
                DateCaptureView(title: "Package Date", initial: item.printedExpiryDate) { date in
                    perform { try store.setPackageDate(item, date) }
                    isCapturingDate = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isCapturingDate = false }
                    }
                }
            }
        }
        .sheet(isPresented: $isPickingGuide) {
            if let product = item.product {
                FoodKeeperPicker(product: product)
            }
        }
        .confirmationDialog(
            "Did you open it?",
            isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Yes, it's open") { finishMove(opened: true) }
            Button("No, still sealed") { finishMove(opened: false) }
        } message: {
            Text("Opened food keeps for less time, so Larder moves its date up.")
        }
        .errorAlert($errorMessage)
    }

    private var quantityText: String {
        let current = item.quantityLabel
        guard item.initialQuantity != item.quantity else { return current }
        return "\(current) of \(item.unit.label(for: item.initialQuantity))"
    }

    private var history: [HistoryEntry] {
        guard let product = item.product else { return [] }
        let purchases = (product.purchases ?? []).map(HistoryEntry.init(purchase:))
        let usages = (product.usages ?? []).map(HistoryEntry.init(usage:))
        return (purchases + usages).sorted { $0.date > $1.date }.prefix(25).map { $0 }
    }

    private func addToShoppingList() {
        do {
            try InventoryStore(context: modelContext).addToShoppingList(
                name: item.displayName,
                quantity: item.initialQuantity,
                unit: item.unit,
                product: item.product
            )
            addedToList = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var store: InventoryStore { InventoryStore(context: modelContext) }

    private func apply(_ action: QuickAction) {
        perform { try InventoryStore(context: modelContext).apply(action, to: item) }
    }

    /// Moving sealed food from the pantry to the fridge usually means it was
    /// just opened, so ask.
    private func move(to location: StorageLocation) {
        if store.shouldAskIfOpened(item, movingTo: location) {
            pendingMove = location
        } else {
            perform { try store.moveItem(item, to: location) }
        }
    }

    private func finishMove(opened: Bool) {
        guard let location = pendingMove else { return }
        pendingMove = nil
        perform { try store.moveItem(item, to: location, opened: opened) }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// What Larder has learned about how fast this product gets used.
private struct UsageSection: View {
    let item: InventoryItem
    let forecast: RunOutForecast
    let estimate: ItemEstimate?
    let onFinished: () -> Void
    let onRecount: () -> Void

    var body: some View {
        Section {
            if let estimate, estimate.isProbablyFinished {
                VStack(alignment: .leading, spacing: 10) {
                    Label("This is probably used up by now", systemImage: "questionmark.circle.fill")
                        .foregroundStyle(Theme.honeyInk)
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        Button("It's finished", action: onFinished)
                            .buttonStyle(.borderedProminent)
                        Button("Still have some", action: onRecount)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            } else if let estimate, estimate.isProjected {
                LabeledContent("Probably left") {
                    Text("~\(item.unit.label(for: estimate.roundedRemaining))")
                }
                .onTapGesture(perform: onRecount)
            }
            LabeledContent("You use about", value: Self.pace(forecast))
            if !forecast.isOutOfStock {
                LabeledContent("Runs out", value: Self.runOut(forecast))
            }
            VStack(alignment: .leading, spacing: 4) {
                ConfidenceBadge(confidence: forecast.confidence)
                Text(Self.basis(forecast))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Usage")
        } footer: {
            Text("Estimated from what you buy and any use you log, so you don't have to record every glass of milk.")
        }
    }

    /// "1 gal every 5 days", "2 each a week", "1 pack a month".
    static func pace(_ forecast: RunOutForecast) -> String {
        let amount = forecast.unit.label(for: forecast.unit.roundedEstimate(forecast.typicalPurchaseQuantity))
        let days = forecast.daysPerPurchase
        guard days.isFinite, days > 0 else { return "—" }
        switch days {
        case ..<1.5: return "\(amount) a day"
        case 6...8: return "\(amount) a week"
        case 13...15: return "\(amount) every two weeks"
        case 27...33: return "\(amount) a month"
        default: return "\(amount) every \(Int(days.rounded())) days"
        }
    }

    static func runOut(_ forecast: RunOutForecast) -> String {
        let days = forecast.daysUntilRunOut(from: Date())
        let relative: String
        switch days {
        case ..<1: relative = "today"
        case ..<2: relative = "tomorrow"
        default: relative = "in \(Int(days.rounded())) days"
        }
        return "\(relative) (\(forecast.runOutDate.formatted(.dateTime.weekday(.abbreviated))))"
    }

    static func basis(_ forecast: RunOutForecast) -> String {
        switch forecast.basis {
        case .usage:
            return "Learned from items you finished or logged using."
        case .purchaseHistory:
            let count = forecast.observationCount + 1
            return "Learned from \(count) purchases. It gets sharper with every trip."
        case .categoryDefault:
            return "A typical pace for this kind of item until you've bought it a few times."
        }
    }
}

struct HistoryEntry: Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let detail: String
    let systemImage: String

    init(purchase: PurchaseEvent) {
        id = purchase.id
        date = purchase.date
        title = "Bought \(purchase.unit.label(for: purchase.quantity))"
        var parts: [String] = []
        if let store = purchase.storeName { parts.append(store) }
        if let cents = purchase.priceCents { parts.append(cents.formattedCents(currencyCode: purchase.currencyCode)) }
        detail = parts.joined(separator: " · ")
        systemImage = "cart"
    }

    init(usage: UsageEvent) {
        id = usage.id
        date = usage.date
        switch usage.type {
        case .usedUp:
            title = "Used up"
            systemImage = "checkmark.circle"
        case .partiallyUsed:
            title = "Used \(usage.unit.label(for: usage.quantity))"
            systemImage = "minus.circle"
        case .discarded:
            title = "Tossed"
            systemImage = "xmark.bin"
        }
        detail = ""
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack {
            Image(systemName: entry.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(entry.title)
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.date.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        if let item = PreviewSupport.firstItem(named: "Whole Milk") {
            ItemDetailView(item: item)
        }
    }
    .modelContainer(PreviewSupport.container)
}
