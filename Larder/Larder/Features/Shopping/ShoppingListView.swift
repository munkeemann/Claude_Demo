import InventoryCore
import SwiftData
import SwiftUI

struct ShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShoppingListItem.addedAt) private var entries: [ShoppingListItem]
    // Observed so suggestions refresh as inventory changes.
    @Query private var items: [InventoryItem]
    @AppStorage(ReminderPreferences.horizonKey) private var horizonDays = 7

    @State private var newItemName = ""
    @State private var errorMessage: String?
    @FocusState private var isAddFieldFocused: Bool

    private var store: InventoryStore { InventoryStore(context: modelContext) }

    var body: some View {
        let toBuy = entries.filter { !$0.isChecked }
        let inCart = entries.filter(\.isChecked)
        let suggestions = (try? ForecastService(context: modelContext).shoppingSuggestions(horizonDays: Double(horizonDays))) ?? []

        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add an item", text: $newItemName)
                            .focused($isAddFieldFocused)
                            .submitLabel(.done)
                            .onSubmit(addTypedItem)
                        Button(action: addTypedItem) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Add")
                    }
                }

                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { suggestion in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.name)
                                    if let brand = requiredBrand(for: suggestion) {
                                        BrandTag(brand: brand)
                                    }
                                    Text(reasonText(suggestion))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    perform { try store.addSuggestions([suggestion]) }
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .font(.title3)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Add \(suggestion.name)")
                            }
                        }
                        Button("Add All \(suggestions.count)") {
                            perform { try store.addSuggestions(suggestions) }
                        }
                    } header: {
                        Label("Suggested", systemImage: "sparkles")
                    } footer: {
                        Text("Items predicted to run out in the next \(horizonDays) days, or regulars you're out of.")
                    }
                }

                Section(toBuy.isEmpty ? "Nothing to buy" : "To buy") {
                    ForEach(toBuy) { entry in
                        ShoppingRow(entry: entry) { toggle(entry) }
                    }
                    .onDelete { offsets in
                        delete(offsets.map { toBuy[$0] })
                    }
                }

                if !inCart.isEmpty {
                    Section("In cart") {
                        ForEach(inCart) { entry in
                            ShoppingRow(entry: entry) { toggle(entry) }
                        }
                        .onDelete { offsets in
                            delete(offsets.map { inCart[$0] })
                        }
                    }
                }
            }
            .themedBackground()
            .navigationTitle("Shopping")
            .toolbar {
                if !inCart.isEmpty {
                    Button("Clear Checked") {
                        perform { try store.clearCheckedShoppingItems() }
                    }
                }
            }
            .animation(.default, value: entries.map(\.isChecked))
            .errorAlert($errorMessage)
        }
    }

    /// The brand to buy, for products where it matters.
    private func requiredBrand(for suggestion: ShoppingSuggestion) -> String? {
        guard let product = try? store.product(id: suggestion.productID), product.brandMatters else { return nil }
        return product.brand
    }

    private func reasonText(_ suggestion: ShoppingSuggestion) -> String {
        let amount = suggestion.unit.label(for: suggestion.quantity)
        switch suggestion.reason {
        case .outOfStock:
            return "\(amount) · you're probably out"
        case .runningOut(let date):
            return "\(amount) · runs out \(date.formatted(.relative(presentation: .named)))"
        }
    }

    private func addTypedItem() {
        let name = newItemName
        perform {
            let product = try store.product(named: name, brand: nil)
            try store.addToShoppingList(name: name, product: product)
        }
        newItemName = ""
        isAddFieldFocused = true
    }

    private func toggle(_ entry: ShoppingListItem) {
        perform { try store.setChecked(entry, !entry.isChecked) }
    }

    private func delete(_ targets: [ShoppingListItem]) {
        perform {
            for entry in targets {
                try store.deleteShoppingItem(entry)
            }
        }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ShoppingRow: View {
    let entry: ShoppingListItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: entry.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(entry.isChecked ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .strikethrough(entry.isChecked)
                        .foregroundStyle(entry.isChecked ? .secondary : .primary)
                    if let product = entry.product, product.brandMatters, let brand = product.brand, !brand.isEmpty {
                        BrandTag(brand: brand)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(entry.isChecked ? .isSelected : [])
    }

    private var detail: String {
        var parts = [entry.quantityLabel]
        if entry.reason != .manual { parts.append(entry.reason.displayName) }
        if let note = entry.note, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

/// "Tillamook only" under a shopping-list item whose brand matters.
struct BrandTag: View {
    let brand: String

    var body: some View {
        Label("\(brand) only", systemImage: "tag.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.honeyInk)
    }
}

#Preview {
    ShoppingListView()
        .modelContainer(PreviewSupport.container)
}
