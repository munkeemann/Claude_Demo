import InventoryCore
import SwiftData
import SwiftUI

/// Confirm a batch of items before anything changes: new items to add, new
/// counts for tracked ones, and tracked items that weren't in the photo.
/// Shelf photos, Quick Add lists and barcode batches all end here.
struct ShelfScanReviewView: View {
    /// Offers to scan again against a location that fits the photo better.
    struct LocationSuggestion {
        var name: String
        var systemImage: String
        var pickedName: String
        var rescan: () -> Void
    }

    @Binding var review: ShelfScanReview
    var photos: [UIImage] = []
    var suggestion: LocationSuggestion? = nil
    /// What found the items, for the summary line ("Claude found 12 products").
    var finder: String = "Claude"
    var onImport: () -> Void

    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]

    private var changeCount: Int {
        review.includedLines.count + review.unseen.filter(\.markFinished).count
    }

    private var foundSummary: String {
        switch review.lines.count {
        case 0: "\(finder) didn't find any products."
        case 1: "\(finder) found 1 product. Tap the circle to skip it, or the item to fix it."
        case let count: "\(finder) found \(count) products. Tap a circle to skip one, or an item to fix it."
        }
    }

    private var hasAdds: Bool { review.lines.contains { $0.action == .add } }
    private var hasUpdates: Bool { review.lines.contains { $0.action == .update } }

    var body: some View {
        List {
            Section {
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(photos.enumerated()), id: \.offset) { _, photo in
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: photos.count == 1 ? 280 : 150, height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } footer: {
                Text(foundSummary)
            }

            if let suggestion {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("This looks like your \(suggestion.name)", systemImage: suggestion.systemImage)
                            .font(.headline)
                            .foregroundStyle(Theme.honeyInk)
                        Text("You picked \(suggestion.pickedName). Scan again to compare with what's tracked in the \(suggestion.name) and file new items there.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Scan Again for \(suggestion.name)", action: suggestion.rescan)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }

            if hasAdds {
                Section {
                    ForEach($review.lines) { $line in
                        if line.action == .add {
                            row($line)
                        }
                    }
                } header: {
                    Text("New to your inventory")
                }
            }

            if hasUpdates {
                Section {
                    ForEach($review.lines) { $line in
                        if line.action == .update {
                            row($line)
                        }
                    }
                } header: {
                    Text("Updated counts")
                } footer: {
                    Text("A fresh count resets the usage estimate for that item.")
                }
            }

            if !review.unseen.isEmpty {
                Section {
                    ForEach($review.unseen) { $item in
                        Toggle(isOn: $item.markFinished) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.hint.name)
                                Text("Recorded: \(item.hint.unit.label(for: item.hint.quantity))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(Theme.green)
                    }
                } header: {
                    Text("Not in the photo")
                } footer: {
                    Text("They may just be out of frame. Switch on the ones that are gone.")
                }
            }

            Section {
                Toggle("I just bought these", isOn: $review.justBought)
                    .tint(Theme.green)
            } footer: {
                Text(review.justBought
                    ? "New items and any extra stock count as today's purchases, which helps Larder learn how fast you use things."
                    : "Treated as a stock-take of things you already had. Turn this on after a shopping trip without a receipt.")
            }
        }
        .themedBackground()
        .safeAreaInset(edge: .bottom) {
            Button(action: onImport) {
                Text(changeCount == 1 ? "Save 1 Change" : "Save \(changeCount) Changes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!review.canImport)
            .padding()
            .background(.bar)
        }
    }

    private func row(_ line: Binding<ShelfScanLine>) -> some View {
        HStack(spacing: 8) {
            IncludeToggle(isOn: line.include)
            NavigationLink {
                ShelfLineEditor(line: line, locations: locations, defaultLocationID: review.locationID)
            } label: {
                ShelfLineRow(line: line.wrappedValue, locationName: locationName(for: line.wrappedValue))
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                line.wrappedValue.include.toggle()
            } label: {
                Label(line.wrappedValue.include ? "Skip" : "Include", systemImage: line.wrappedValue.include ? "minus.circle" : "plus.circle")
            }
            .tint(line.wrappedValue.include ? .gray : Theme.green)
        }
    }

    /// Shown when items in one review go to different places.
    private func locationName(for line: ShelfScanLine) -> String? {
        guard line.action == .add, let id = line.locationID, id != review.locationID else { return nil }
        return locations.first { $0.id == id }?.name
    }
}

private struct ShelfLineRow: View {
    let line: ShelfScanLine
    let locationName: String?

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: line.category, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(line.name.isEmpty ? "Unnamed" : line.name)
                        .strikethrough(!line.include)
                    if line.confidence == .low {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.honeyInk)
                            .accessibilityLabel("Low confidence")
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .opacity(line.include ? 1 : 0.6)
    }

    private var detail: String {
        let amount = line.unit.label(for: line.quantity)
        switch line.action {
        case .update:
            let before = line.previousQuantity.map { line.unit.label(for: $0) } ?? "?"
            return "Was \(before) · now \(amount)"
        case .add:
            var parts = [amount]
            if let full = line.fullQuantity { parts[0] += " of \(line.unit.label(for: full))" }
            if let size = line.packageSize { parts.append(size) }
            if !line.brand.isEmpty { parts.append(line.brand) }
            if let locationName { parts.append(locationName) }
            if line.name.isEmpty, let barcode = line.barcode { parts.append("Barcode \(barcode)") }
            return parts.joined(separator: " · ")
        }
    }
}

/// Edit one detected product. Tracked items keep their product and unit;
/// only the count changes.
private struct ShelfLineEditor: View {
    @Binding var line: ShelfScanLine
    let locations: [StorageLocation]
    let defaultLocationID: UUID?

    var body: some View {
        Form {
            Section {
                Toggle(line.action == .add ? "Add this item" : "Update this count", isOn: $line.include)
                    .tint(Theme.green)
            }

            if line.action == .add {
                Section("Product") {
                    TextField("Name", text: $line.name)
                    TextField("Brand", text: $line.brand)
                    Picker("Category", selection: $line.category) {
                        ForEach(ProductCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.systemImage).tag(category)
                        }
                    }
                    Picker("Location", selection: Binding(
                        get: { line.locationID ?? defaultLocationID },
                        set: { line.locationID = $0 }
                    )) {
                        ForEach(locations, id: \StorageLocation.id) { location in
                            Label(location.name, systemImage: location.systemImage).tag(Optional(location.id))
                        }
                    }
                }
            }

            Section {
                HStack {
                    TextField("Quantity", value: $line.quantity, format: .number.precision(.fractionLength(0...3)))
                        .keyboardType(.decimalPad)
                    if line.action == .add {
                        Picker("Unit", selection: $line.unit) {
                            ForEach(MeasureUnit.allCases) { unit in
                                Text(unit.symbol).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    } else {
                        Text(line.unit.symbol)
                            .foregroundStyle(.secondary)
                    }
                }
                if line.action == .add {
                    TextField("Package size", text: Binding(
                        get: { line.packageSize ?? "" },
                        set: { line.packageSize = $0.isEmpty ? nil : $0 }
                    ))
                }
            } header: {
                Text(line.action == .add ? "Amount" : "Amount left now")
            } footer: {
                if let previous = line.previousQuantity {
                    Text("Recorded before this scan: \(line.unit.label(for: previous)).")
                }
            }
        }
        .themedBackground()
        .navigationTitle(line.name.isEmpty ? "Item" : line.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ShelfScanReviewView(
            review: .constant(ShelfScanReview(result: SampleShelfScan.result, hints: [], locationID: nil)),
            onImport: {}
        )
    }
    .modelContainer(PreviewSupport.container)
}
