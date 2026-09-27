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
    @State private var isScanningDate = false
    @State private var askOpenedFor: UUID?
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
                if !draft.brand.trimmingCharacters(in: .whitespaces).isEmpty {
                    Toggle("Stick to this brand", isOn: Binding(
                        get: { draft.brandMatters ?? false },
                        set: { draft.brandMatters = $0 }
                    ))
                    .tint(Theme.green)
                }
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
                    ForEach(locations, id: \StorageLocation.id) { location in
                        Label(location.name, systemImage: location.systemImage).tag(Optional(location.id))
                    }
                }
                DatePicker("Purchased", selection: $draft.purchaseDate, displayedComponents: .date)
            }

            Section {
                Toggle("Date on the package", isOn: $hasExpiry.animation())
                if hasExpiry {
                    DatePicker(
                        "Package date",
                        selection: Binding(
                            get: { draft.expiryDate ?? defaultExpiry },
                            set: { draft.expiryDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                }
                Button {
                    isScanningDate = true
                } label: {
                    Label(hasExpiry ? "Scan the Date Again" : "Scan the Date", systemImage: "camera.viewfinder")
                }
                Toggle("Opened", isOn: Binding(
                    get: { draft.openedDate != nil },
                    set: { draft.openedDate = $0 ? (draft.openedDate ?? Date()) : nil }
                ).animation())
                if let opened = draft.openedDate {
                    DatePicker("Opened on", selection: Binding(get: { opened }, set: { draft.openedDate = $0 }), displayedComponents: .date)
                }
            } header: {
                Text("Expiry")
            } footer: {
                if let estimate = estimatePreview {
                    Text(estimate)
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
            if isOn { draft.expiryIsEstimate = false }
        }
        .onChange(of: draft.locationID) { oldValue, newValue in
            // Sealed food going from the pantry into the fridge was usually just opened.
            guard !isAdding, draft.openedDate == nil, draft.category.isFood,
                  climate(of: oldValue) == .room, climate(of: newValue) == .fridge
            else { return }
            askOpenedFor = newValue
        }
        .confirmationDialog(
            "Did you open it?",
            isPresented: Binding(get: { askOpenedFor != nil }, set: { if !$0 { askOpenedFor = nil } }),
            titleVisibility: .visible
        ) {
            Button("Yes, it's open") {
                draft.openedDate = Date()
                askOpenedFor = nil
            }
            Button("No, still sealed") { askOpenedFor = nil }
        } message: {
            Text("Opened food keeps for less time, so Larder moves its date up.")
        }
        .sheet(isPresented: $isScanningDate) {
            NavigationStack {
                DateCaptureView(title: "Package Date", initial: draft.expiryDate) { date in
                    draft.expiryDate = date
                    draft.expiryIsEstimate = false
                    hasExpiry = true
                    isScanningDate = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isScanningDate = false }
                    }
                }
            }
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

    private func climate(of locationID: UUID?) -> StorageClimate? {
        locations.first { $0.id == locationID }?.climate
    }

    /// What Larder will use without a package date.
    private var estimatePreview: String? {
        guard !hasExpiry, draft.tracksExpiry, !draft.trimmedName.isEmpty else { return nil }
        let place = climate(of: draft.locationID) ?? draft.category.defaultClimate
        let inputs = ExpiryInputs(
            category: draft.category,
            foodKeeper: FoodKeeper.match(name: draft.trimmedName, brand: draft.trimmedBrand, category: draft.category),
            climate: place,
            purchaseDate: draft.purchaseDate,
            openedDate: draft.openedDate
        )
        let result = ExpiryCalculator.compute(inputs, strictness: InventoryStore(context: modelContext).expiryStrictness())
        guard let date = result.date else { return nil }
        var text = "Without a package date, Larder estimates \(date.formatted(date: .abbreviated, time: .omitted))"
        if let explanation = result.explanation { text += " (\(explanation))" }
        return text + "."
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
