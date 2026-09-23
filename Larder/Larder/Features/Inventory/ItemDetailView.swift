import InventoryCore
import SwiftUI

struct ItemDetailView: View {
    let item: InventoryItem

    @Environment(\.modelContext) private var modelContext
    @State private var editor: EditorSheet?
    @State private var isUsingSome = false
    @State private var errorMessage: String?

    var body: some View {
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
                if let expiry = item.expiryDate {
                    LabeledContent("Expires") {
                        HStack(spacing: 6) {
                            Text(expiry.formatted(date: .abbreviated, time: .omitted))
                            ExpiryBadge(date: expiry)
                        }
                    }
                }
                if let size = item.product?.packageSizeText {
                    LabeledContent("Package size", value: size)
                }
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .foregroundStyle(.secondary)
                }
            }

            if item.status.isActive {
                Section("Quick actions") {
                    Button { isUsingSome = true } label: {
                        Label("Used some…", systemImage: "minus.circle")
                    }
                    Button { apply(.usedUp) } label: {
                        Label("Used it all", systemImage: "checkmark.circle")
                    }
                    Button { apply(.tossed) } label: {
                        Label("Tossed it", systemImage: "xmark.bin")
                    }
                    .tint(.orange)
                }
            }

            Section {
                Button { editor = .add(item.restockDraft()) } label: {
                    Label("Buy again", systemImage: "arrow.clockwise")
                }
            }

            if !history.isEmpty {
                Section("History") {
                    ForEach(history) { entry in
                        HistoryRow(entry: entry)
                    }
                }
            }
        }
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

    private func apply(_ action: QuickAction) {
        do {
            try InventoryStore(context: modelContext).apply(action, to: item)
        } catch {
            errorMessage = error.localizedDescription
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
