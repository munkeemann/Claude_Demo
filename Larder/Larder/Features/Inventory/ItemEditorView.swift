import InventoryCore
import SwiftData
import SwiftUI

/// Add/edit form for an inventory item. Callers embed it in a NavigationStack.
struct ItemEditorView: View {
    enum Mode {
        case add(ItemDraft)
        case edit(InventoryItem)
    }

    let mode: Mode
    /// Called after saving or cancelling. Defaults to dismissing the view.
    var onFinish: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]

    @State private var draft: ItemDraft
    @State private var hasExpiry: Bool
    @State private var price: Double?
    @State private var errorMessage: String?

    init(mode: Mode, onFinish: (() -> Void)? = nil) {
        self.mode = mode
        self.onFinish = onFinish
        let initial: ItemDraft
        switch mode {
        case .add(let draft): initial = draft
        case .edit(let item): initial = item.draft
        }
        _draft = State(initialValue: initial)
        _hasExpiry = State(initialValue: initial.expiryDate != nil)
        _price = State(initialValue: initial.priceCents.map { Double($0) / 100 })
    }

    private var isAdding: Bool {
        if case .add = mode { return true }
        return false
    }

    private var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                    .textInputAutocapitalization(.words)
                TextField("Brand (optional)", text: $draft.brand)
                    .textInputAutocapitalization(.words)
                Picker("Category", selection: $draft.category) {
                    Section("Food") {
                        ForEach(ProductCategory.foodCategories) { category in
                            Label(category.displayName, systemImage: category.systemImage).tag(category)
                        }
                    }
                    Section("Household") {
                        ForEach(ProductCategory.householdCategories) { category in
                            Label(category.displayName, systemImage: category.systemImage).tag(category)
                        }
                    }
                }
            }

            Section("Amount") {
                HStack {
                    TextField("Quantity", value: $draft.quantity, format: .number.precision(.fractionLength(0...3)))
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $draft.unit) {
                        ForEach(MeasureUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if let size = draft.packageSizeText, !size.isEmpty {
                    LabeledContent("Package size", value: size)
                }
            }

            Section("Storage") {
                Picker("Location", selection: $draft.locationID) {
                    Text("None").tag(UUID?.none)
                    ForEach(locations) { location in
                        Label(location.name, systemImage: location.systemImage).tag(Optional(location.id))
                    }
                }
                DatePicker("Purchased", selection: $draft.purchaseDate, displayedComponents: .date)
                Toggle("Expiry date", isOn: $hasExpiry.animation())
                if hasExpiry {
                    DatePicker(
                        "Expires",
                        selection: Binding(
                            get: { draft.expiryDate ?? defaultExpiry },
                            set: { draft.expiryDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                }
            }

            if isAdding {
                Section("Purchase") {
                    TextField("Price (optional)", value: $price, format: .currency(code: currencyCode))
                        .keyboardType(.decimalPad)
                }
            }

            Section {
                Toggle("Use in recipes", isOn: $draft.isIngredient)
                Toggle("Predict when it runs out", isOn: $draft.tracksRunOut)
                Toggle("Track expiry", isOn: $draft.tracksExpiry)
            } header: {
                Text("Tracking")
            } footer: {
                Text("Defaults come from the category.")
            }

            Section("Notes") {
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(2...5)
                if let barcode = draft.barcode {
                    LabeledContent("Barcode", value: barcode)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !draft.issues.isEmpty && !draft.trimmedName.isEmpty {
                Section {
                    ForEach(draft.issues, id: \.self) { issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.honeyInk)
                    }
                }
            }
        }
        .themedBackground()
        .navigationTitle(isAdding ? "Add Item" : "Edit Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { finish() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!draft.isValid)
            }
        }
        .onChange(of: draft.category) { oldValue, newValue in
            guard isAdding, oldValue != newValue else { return }
            draft.applyCategoryDefaults()
            draft.locationID = defaultLocationID(for: newValue)
        }
        .onChange(of: hasExpiry) { _, isOn in
            draft.expiryDate = isOn ? (draft.expiryDate ?? defaultExpiry) : nil
        }
        .onAppear {
            if isAdding && draft.locationID == nil {
                draft.locationID = defaultLocationID(for: draft.category)
            }
        }
        .errorAlert($errorMessage)
    }

    private var defaultExpiry: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: draft.purchaseDate) ?? draft.purchaseDate
    }

    private func defaultLocationID(for category: ProductCategory) -> UUID? {
        (try? InventoryStore(context: modelContext).defaultLocation(for: category))?.id
    }

    private func save() {
        var final = draft
        final.priceCents = price.map { Int(($0 * 100).rounded()) }
        if !hasExpiry { final.expiryDate = nil }
        let store = InventoryStore(context: modelContext)
        do {
            switch mode {
            case .add:
                try store.addItem(from: final, source: final.barcode == nil ? .manual : .barcode)
            case .edit(let item):
                try store.update(item, from: final)
            }
            finish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish() {
        if let onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }
}

#Preview("Add") {
    NavigationStack {
        ItemEditorView(mode: .add(ItemDraft(name: "Whole Milk", category: .dairy)))
    }
    .modelContainer(PreviewSupport.container)
}
