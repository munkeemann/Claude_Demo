import InventoryCore
import SwiftData
import SwiftUI

/// The item screen's expiry section: the use-by date, what it's based on,
/// the package date and USDA's storage guidance.
struct ExpirySection: View {
    let item: InventoryItem
    let result: ExpiryResult?
    var onCaptureDate: () -> Void
    var onClearDate: () -> Void
    var onPickGuide: () -> Void
    var strictness: ExpiryStrictness

    private var climate: StorageClimate {
        item.location?.climate ?? item.product?.category.defaultClimate ?? .room
    }

    var body: some View {
        Section {
            if let expiry = item.expiryDate {
                LabeledContent("Use by") {
                    HStack(spacing: 6) {
                        Text(expiry.formatted(date: .abbreviated, time: .omitted))
                        ExpiryBadge(date: expiry)
                    }
                }
            } else {
                Text(noDateText)
                    .foregroundStyle(.secondary)
            }
            if let explanation = result?.explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let printed = item.printedExpiryDate {
                LabeledContent("Date on the package", value: printed.formatted(date: .abbreviated, time: .omitted))
                Button("Change Package Date", action: onCaptureDate)
                Button("Remove Package Date", role: .destructive, action: onClearDate)
            } else if item.product?.category.isFood ?? false {
                Button(action: onCaptureDate) {
                    Label("Add the Package Date", systemImage: "calendar.badge.plus")
                }
            }

            if let product = item.product, product.category.isFood {
                Button(action: onPickGuide) {
                    LabeledContent("USDA storage guide") {
                        Text(product.foodKeeper?.name ?? "None")
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.primary)
                if let tip = product.foodKeeper?.tips[climate] {
                    Text(tip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Expiry")
        } footer: {
            Text("Dates follow your home's setting: \(strictness.label). Change it in Settings → Expiration Dates.")
        }
    }

    private var noDateText: String {
        if item.expiryTrackingOff { return "No date. It was added with expiry left blank." }
        if result?.basis == ExpiryResult.Basis.none, result?.explanation != nil { return "Keeps indefinitely." }
        return "No expiry date."
    }
}

/// Pick the USDA FoodKeeper entry a product's dates come from.
struct FoodKeeperPicker: View {
    let product: Product

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var query = ""
    @State private var errorMessage: String?

    private var results: [FoodKeeperEntry] {
        Array(FoodKeeper.search(query).prefix(80))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        choose(nil)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("None")
                                Text("Use Claude's or Larder's estimate")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if product.foodKeeperID == 0 { Image(systemName: "checkmark").foregroundStyle(Theme.green) }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                Section {
                    ForEach(results) { entry in
                        Button {
                            choose(entry)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.displayName)
                                    Text(Self.summary(entry))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if product.foodKeeperID == entry.id { Image(systemName: "checkmark").foregroundStyle(Theme.green) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("Storage times from \(FoodKeeper.source), public domain.")
                }
            }
            .themedBackground()
            .searchable(text: $query, prompt: "Search USDA foods")
            .navigationTitle("Storage Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if query.isEmpty { query = product.foodKeeper == nil ? product.name : "" }
            }
            .errorAlert($errorMessage)
        }
    }

    private func choose(_ entry: FoodKeeperEntry?) {
        do {
            try InventoryStore(context: modelContext).setFoodKeeperEntry(entry, for: product)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// "Pantry 1–2 months · Fridge 1–2 weeks · Freezer 10–12 months".
    static func summary(_ entry: FoodKeeperEntry) -> String {
        let places: [(String, StorageSlot)] = [("Pantry", .pantry), ("Fridge", .fridge), ("Opened", .fridgeOpened), ("Freezer", .freezer)]
        let parts = places.compactMap { name, slot -> String? in
            switch entry.guidance[slot] {
            case .days(let range): "\(name) \(ExpiryCalculator.describe(range))"
            case .packageDate: "\(name) until package date"
            case .indefinitely: "\(name) indefinitely"
            case .whenRipe: "\(name) until ripe"
            case .notRecommended, nil: nil
            }
        }
        return parts.isEmpty ? entry.categoryName : parts.joined(separator: " · ")
    }
}
