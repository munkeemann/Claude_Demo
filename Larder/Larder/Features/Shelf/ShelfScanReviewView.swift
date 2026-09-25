import InventoryCore
import SwiftUI

/// Confirm what Claude saw on the shelf: new items to add, new counts for
/// tracked ones, and tracked items that weren't in the photo.
struct ShelfScanReviewView: View {
    @Binding var review: ShelfScanReview
    let photo: UIImage?
    var onImport: () -> Void

    private var changeCount: Int {
        review.includedLines.count + review.unseen.filter(\.markFinished).count
    }

    private var hasAdds: Bool { review.lines.contains { $0.action == .add } }
    private var hasUpdates: Bool { review.lines.contains { $0.action == .update } }

    var body: some View {
        List {
            if let photo {
                Section {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
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
        NavigationLink {
            ShelfLineEditor(line: line)
        } label: {
            ShelfLineRow(line: line.wrappedValue)
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
}

private struct ShelfLineRow: View {
    let line: ShelfScanLine

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: line.include ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(line.include ? Theme.green : Color.secondary)
                .font(.title3)
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
            return parts.joined(separator: " · ")
        }
    }
}

/// Edit one detected product. Tracked items keep their product and unit;
/// only the count changes.
private struct ShelfLineEditor: View {
    @Binding var line: ShelfScanLine

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
            photo: nil,
            onImport: {}
        )
    }
}
