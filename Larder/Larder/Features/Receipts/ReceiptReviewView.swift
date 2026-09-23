import InventoryCore
import SwiftUI

/// Confirm, edit or drop each extracted line before anything is saved.
struct ReceiptReviewView: View {
    @Binding var review: ReceiptReview
    let locations: [StorageLocation]
    var onImport: () -> Void

    @State private var isShowingRawText = false

    private var includedCount: Int { review.includedLines.count }

    var body: some View {
        List {
            Section {
                TextField("Store", text: $review.storeName)
                DatePicker("Date", selection: $review.purchaseDate, displayedComponents: .date)
            }

            Section {
                ForEach($review.lines) { $line in
                    NavigationLink {
                        ReceiptLineEditor(line: $line, locations: locations)
                    } label: {
                        ReceiptLineRow(line: line, locationName: locationName(for: line), currencyCode: review.currencyCode)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            line.include.toggle()
                        } label: {
                            Label(line.include ? "Skip" : "Include", systemImage: line.include ? "minus.circle" : "plus.circle")
                        }
                        .tint(line.include ? .gray : .green)
                    }
                }
            } header: {
                Text("\(review.lines.count) items found")
            } footer: {
                totalsFooter
            }

            Section {
                DisclosureGroup("Recognized text", isExpanded: $isShowingRawText) {
                    Text(review.rawText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onImport) {
                Text(includedCount == 1 ? "Add 1 Item" : "Add \(includedCount) Items")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!review.canImport)
            .padding()
            .background(.bar)
        }
    }

    @ViewBuilder
    private var totalsFooter: some View {
        let check = review.totalsCheck
        VStack(alignment: .leading, spacing: 4) {
            if let subtotal = check.subtotalCents {
                Text("Items \(check.itemsCents.formattedCents(currencyCode: review.currencyCode)) · Receipt subtotal \(subtotal.formattedCents(currencyCode: review.currencyCode))")
            }
            if !check.isConsistent, let difference = check.differenceCents {
                Label(
                    "Items differ from the subtotal by \(abs(difference).formattedCents(currencyCode: review.currencyCode)). A line may be missing or misread.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
            Text("Swipe to skip items. Tap to edit; your edits are remembered for next time.")
        }
    }

    private func locationName(for line: ReceiptReviewLine) -> String {
        locations.first { $0.id == line.locationID }?.name ?? line.locationKind.defaultName
    }
}

private struct ReceiptLineRow: View {
    let line: ReceiptReviewLine
    let locationName: String
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: line.include ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(line.include ? Color.accentColor : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(line.name.isEmpty ? "Unnamed" : line.name)
                        .strikethrough(!line.include)
                    if line.origin == .remembered {
                        Image(systemName: "brain")
                            .font(.caption)
                            .foregroundStyle(.purple)
                            .accessibilityLabel("Remembered from a previous receipt")
                    }
                    if line.confidence == .low {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Low confidence")
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(line.rawText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if let cents = line.priceCents {
                Text(cents.formattedCents(currencyCode: currencyCode))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(line.include ? .primary : .secondary)
            }
        }
        .opacity(line.include ? 1 : 0.6)
    }

    private var detail: String {
        var parts = [line.unit.label(for: line.quantity)]
        if !line.brand.isEmpty { parts.append(line.brand) }
        parts.append(locationName)
        return parts.joined(separator: " · ")
    }
}

/// Edit one receipt line.
struct ReceiptLineEditor: View {
    @Binding var line: ReceiptReviewLine
    let locations: [StorageLocation]

    var body: some View {
        Form {
            Section {
                Toggle("Add this item", isOn: $line.include)
            }

            Section {
                TextField("Name", text: $line.name)
                TextField("Brand", text: $line.brand)
                Picker("Category", selection: $line.category) {
                    ForEach(ProductCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.systemImage).tag(category)
                    }
                }
            } header: {
                Text("Product")
            } footer: {
                Text("Receipt text: \(line.rawText)")
            }

            Section("Amount") {
                HStack {
                    TextField("Quantity", value: $line.quantity, format: .number.precision(.fractionLength(0...3)))
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $line.unit) {
                        ForEach(MeasureUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                TextField("Package size", text: Binding(
                    get: { line.packageSize ?? "" },
                    set: { line.packageSize = $0.isEmpty ? nil : $0 }
                ))
                TextField("Price", value: Binding(
                    get: { line.priceCents.map { Double($0) / 100 } },
                    set: { line.priceCents = $0.map { Int(($0 * 100).rounded()) } }
                ), format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
            }

            Section {
                Picker("Location", selection: $line.locationID) {
                    Text("None").tag(UUID?.none)
                    ForEach(locations) { location in
                        Label(location.name, systemImage: location.systemImage).tag(Optional(location.id))
                    }
                }
                if line.category.defaultTracksExpiry {
                    Stepper(value: Binding(
                        get: { line.shelfLifeDays ?? 0 },
                        set: { line.shelfLifeDays = $0 > 0 ? $0 : nil }
                    ), in: 0...365) {
                        LabeledContent("Keeps for", value: line.shelfLifeDays.map { "\($0) days" } ?? "Unknown")
                    }
                }
            } header: {
                Text("Storage")
            }
        }
        .navigationTitle(line.name.isEmpty ? "Item" : line.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ReceiptReviewView(
            review: .constant(ReceiptReview(
                extraction: SampleReceipt.extraction,
                rawText: SampleReceipt.ocrText,
                hints: [],
                today: Date(),
                defaultCurrency: "USD"
            )),
            locations: [],
            onImport: {}
        )
    }
}
