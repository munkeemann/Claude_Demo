import InventoryCore
import SwiftData
import SwiftUI

/// The main inventory list, grouped by storage location.
struct InventoryHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryItem.createdAt, order: .reverse) private var items: [InventoryItem]
    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]

    @State private var filter = InventoryFilter()
    @State private var editor: EditorSheet?
    @State private var flow: Flow?
    @State private var isShowingFilters = false
    @AppStorage(AddPreferences.defaultMethodKey) private var defaultMethodRaw = AddMethod.default.rawValue
    @State private var useSomeItem: InventoryItem?
    @State private var recountItem: InventoryItem?
    @State private var errorMessage: String?

    private var store: InventoryStore { InventoryStore(context: modelContext) }
    private var service: ForecastService { ForecastService(context: modelContext) }

    var body: some View {
        let snapshot = items.isEmpty ? ForecastSnapshot.empty : ((try? service.snapshot()) ?? .empty)
        NavigationStack {
            content(snapshot)
                .themedBackground()
                .navigationTitle("Inventory")
                .searchable(text: $filter.searchText, prompt: "Search items, brands, categories")
                .toolbar { toolbar }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !items.isEmpty { locationChips }
                }
                .navigationDestination(for: InventoryItem.self) { item in
                    ItemDetailView(item: item)
                }
        }
        .sheet(item: $editor) { sheet in
            NavigationStack {
                ItemEditorView(mode: sheet.mode)
            }
        }
        .sheet(item: $flow) { flow in
            switch flow {
            case .quickAdd: QuickAddView()
            case .shelf: ShelfScanFlow()
            case .barcodes: ScanBarcodeFlow()
            case .receipt: ReceiptScanFlow()
            case .tossOut: ScanOutFlow(initialDisposition: .tossed)
            case .useUp: ScanOutFlow(initialDisposition: .used)
            case .recipe: RecipeScanFlow()
            }
        }
        .sheet(item: $useSomeItem) { item in
            UseSomeSheet(item: item)
        }
        .sheet(item: $recountItem) { item in
            RecountSheet(item: item)
        }
        .sheet(isPresented: $isShowingFilters) {
            InventoryFilterSheet(filter: $filter, locations: locations)
        }
        .errorAlert($errorMessage)
        .onAppear { open(AppRouter.shared.pendingAction) }
        .onChange(of: AppRouter.shared.pendingAction) { _, action in open(action) }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ snapshot: ForecastSnapshot) -> some View {
        if items.isEmpty {
            ContentUnavailableView {
                VStack(spacing: 12) {
                    LarderMark(size: 88)
                    Text("Nothing tracked yet")
                        .foregroundStyle(Theme.heading)
                }
            } description: {
                Text("Photograph a shelf, scan a receipt or barcode, or add items by hand. You can also load sample data to explore.")
            } actions: {
                Button("Quick Add") { flow = .quickAdd }
                    .buttonStyle(.borderedProminent)
                Button("Scan a Shelf") { flow = .shelf }
                Button("Scan Receipt") { flow = .receipt }
                Button("Scan Barcodes") { flow = .barcodes }
                Button("Add One Item") { editor = .add(ItemDraft()) }
                Button("Load Sample Data") { perform { try store.loadSampleData() } }
            }
        } else if sections.isEmpty {
            if filter.searchText.isEmpty {
                ContentUnavailableView {
                    Label("No matching items", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Try clearing some filters.")
                } actions: {
                    Button("Clear Filters") { filter = InventoryFilter(sort: filter.sort) }
                }
            } else {
                ContentUnavailableView.search(text: filter.searchText)
            }
        } else {
            List {
                Section {
                    InventorySummaryCard(items: items, snapshot: snapshot)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            NavigationLink(value: item) {
                                InventoryItemRow(item: item, estimate: snapshot.estimates[item.id])
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button { apply(.usedUp, to: item) } label: {
                                    Label("Used Up", systemImage: "checkmark.circle")
                                }
                                .tint(Theme.green)
                                Button { useSomeItem = item } label: {
                                    Label("Used Some", systemImage: "minus.circle")
                                }
                                .tint(Theme.greenDeep)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { perform { try store.delete(item) } } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { apply(.tossed, to: item) } label: {
                                    Label("Tossed", systemImage: "xmark.bin")
                                }
                                .tint(Theme.terracotta)
                            }
                            .contextMenu { contextMenu(for: item) }
                        }
                    } header: {
                        Label(section.title, systemImage: section.systemImage)
                            .foregroundStyle(Theme.heading)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.default, value: sections.map(\.id))
        }
    }

    @ViewBuilder
    private func contextMenu(for item: InventoryItem) -> some View {
        Button { useSomeItem = item } label: { Label("Used Some…", systemImage: "minus.circle") }
        Button { recountItem = item } label: { Label("How Much Is Left?", systemImage: "gauge.with.dots.needle.50percent") }
        Button { apply(.usedUp, to: item) } label: { Label("Used Up", systemImage: "checkmark.circle") }
        Button { apply(.tossed, to: item) } label: { Label("Tossed", systemImage: "xmark.bin") }
        if item.location?.climate != .freezer {
            Button { perform { try store.freeze(item) } } label: { Label("Freeze It", systemImage: "snowflake") }
        }
        Divider()
        Button { editor = .edit(item) } label: { Label("Edit", systemImage: "pencil") }
        Button { editor = .add(item.restockDraft()) } label: { Label("Buy Again", systemImage: "arrow.clockwise") }
        Divider()
        Button(role: .destructive) { perform { try store.delete(item) } } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var locationChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: filter.locationIDs.isEmpty) {
                    filter.locationIDs = []
                }
                ForEach(locations, id: \StorageLocation.id) { location in
                    FilterChip(
                        title: location.name,
                        systemImage: location.systemImage,
                        isSelected: filter.locationIDs == [location.id]
                    ) {
                        filter.locationIDs = filter.locationIDs == [location.id] ? [] : [location.id]
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Theme.background)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { isShowingFilters = true } label: {
                Label(
                    "Filter",
                    systemImage: filter.hasActiveFilters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { flow = .tossOut } label: { Label("Toss Things Out", systemImage: "xmark.bin") }
                Button { flow = .useUp } label: { Label("Used Things Up", systemImage: "checkmark.circle") }
                Button { flow = .recipe } label: { Label("I Cooked a Recipe", systemImage: "frying.pan") }
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            // Tap for your usual way of adding; hold for all of them.
            Menu {
                ForEach(AddMethod.allCases) { method in
                    Button { start(method) } label: {
                        Label(method.label, systemImage: method.systemImage)
                    }
                }
            } label: {
                Label("Add", systemImage: "plus")
            } primaryAction: {
                start(AddMethod(rawValue: defaultMethodRaw) ?? .default)
            }
        }
    }

    // MARK: - Grouping

    private var sections: [InventorySection] {
        let visible = filter.apply(items) { $0.summary }
        var grouped: [UUID: [InventoryItem]] = [:]
        var unassigned: [InventoryItem] = []
        for item in visible {
            if let id = item.location?.id {
                grouped[id, default: []].append(item)
            } else {
                unassigned.append(item)
            }
        }
        var result = locations.compactMap { location -> InventorySection? in
            guard let items = grouped[location.id], !items.isEmpty else { return nil }
            return InventorySection(id: location.id.uuidString, title: location.name, systemImage: location.systemImage, items: items)
        }
        if !unassigned.isEmpty {
            result.append(InventorySection(id: "unassigned", title: "No Location", systemImage: "questionmark.folder", items: unassigned))
        }
        return result
    }

    // MARK: - Actions

    /// The flows presented as sheets from this screen.
    enum Flow: String, Identifiable {
        case quickAdd, shelf, barcodes, receipt, tossOut, useUp, recipe
        var id: String { rawValue }
    }

    private func start(_ method: AddMethod) {
        switch method {
        case .quickAdd: flow = .quickAdd
        case .shelf: flow = .shelf
        case .barcodes: flow = .barcodes
        case .receipt: flow = .receipt
        case .manual: editor = .add(ItemDraft())
        }
    }

    /// Opens what a Lock Screen button or shortcut asked for, in place of
    /// anything already showing here.
    private func open(_ action: LarderAction?) {
        guard let action else { return }
        AppRouter.shared.pendingAction = nil
        editor = nil
        useSomeItem = nil
        recountItem = nil
        isShowingFilters = false
        switch action {
        case .add: start(AddMethod(rawValue: defaultMethodRaw) ?? .default)
        case .barcodes: flow = .barcodes
        case .shelf: flow = .shelf
        case .receipt: flow = .receipt
        case .quickAdd: flow = .quickAdd
        case .tossOut: flow = .tossOut
        case .useUp: flow = .useUp
        case .recipe: flow = .recipe
        }
    }

    private func apply(_ action: QuickAction, to item: InventoryItem) {
        perform { try store.apply(action, to: item) }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try withAnimation { try work() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The icon-green card at the top of the inventory: what's in stock and
/// what needs attention.
struct InventorySummaryCard: View {
    let items: [InventoryItem]
    let snapshot: ForecastSnapshot
    var now = Date()

    var body: some View {
        let active = items.filter(\.status.isActive)
        let soon = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now
        let expiring = active.filter { ($0.expiryDate ?? .distantFuture) < soon }.count
        let finished = active.filter { snapshot.estimates[$0.id]?.isProbablyFinished == true }.count
        let runningLow = snapshot.forecasts.filter {
            !$0.forecast.isOutOfStock && $0.forecast.daysUntilRunOut(from: now) <= 3
        }.count

        BrandCard {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(active.count) \(active.count == 1 ? "item" : "items") on hand")
                        .font(.title3.weight(.bold))
                    HStack(spacing: 14) {
                        stat(expiring, "expiring", systemImage: "clock")
                        stat(runningLow, "running low", systemImage: "chart.line.downtrend.xyaxis")
                        if finished > 0 {
                            stat(finished, "to check", systemImage: "questionmark.circle")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                }
                Spacer(minLength: 0)
                LarderMark(size: 52)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ count: Int, _ label: String, systemImage: String) -> some View {
        Label("\(count) \(label)", systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(count > 0 ? Theme.cream : Theme.cream.opacity(0.7))
    }
}

struct InventorySection: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let items: [InventoryItem]
}

/// Identifies which item editor sheet is showing.
enum EditorSheet: Identifiable {
    case add(ItemDraft)
    case edit(InventoryItem)

    var id: String {
        switch self {
        case .add(let draft): "add-\(draft.hashValue)"
        case .edit(let item): "edit-\(item.id.uuidString)"
        }
    }

    var mode: ItemEditorView.Mode {
        switch self {
        case .add(let draft): .add(draft)
        case .edit(let item): .edit(item)
        }
    }
}

#Preview {
    InventoryHomeView()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
