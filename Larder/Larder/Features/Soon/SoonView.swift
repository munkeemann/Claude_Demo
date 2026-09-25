import InventoryCore
import SwiftData
import SwiftUI

/// "Expiring soon" and "Running low soon" in one place.
struct SoonView: View {
    @Environment(\.modelContext) private var modelContext
    // Observed so the lists refresh when inventory or the shopping list changes.
    @Query private var items: [InventoryItem]
    @Query private var shoppingEntries: [ShoppingListItem]
    @AppStorage(ReminderPreferences.horizonKey) private var horizonDays = 7
    @State private var errorMessage: String?

    private var service: ForecastService { ForecastService(context: modelContext) }
    private var store: InventoryStore { InventoryStore(context: modelContext) }

    var body: some View {
        let expiring = (try? service.expiringItems(withinDays: horizonDays)) ?? []
        let forecasts = (try? service.productForecasts()) ?? []
        let horizon = Date().addingTimeInterval(Double(horizonDays) * 86_400)
        let runningLow = forecasts.filter { !$0.forecast.isOutOfStock && $0.forecast.runOutDate <= horizon }
        let outOfStock = forecasts.filter { $0.forecast.isOutOfStock && $0.purchaseCount >= 2 }
        let onList = Set(shoppingEntries.filter { !$0.isChecked }.compactMap { $0.product?.id })

        NavigationStack {
            List {
                if expiring.isEmpty && runningLow.isEmpty && outOfStock.isEmpty {
                    ContentUnavailableView(
                        "Nothing urgent",
                        systemImage: "checkmark.seal",
                        description: Text("Nothing expires or runs out in the next \(horizonDays) days.")
                    )
                    .listRowBackground(Color.clear)
                }

                if !expiring.isEmpty {
                    Section("Expiring soon") {
                        ForEach(expiring) { item in
                            NavigationLink(value: item) {
                                InventoryItemRow(item: item)
                            }
                            .swipeActions(edge: .leading) {
                                Button { apply(.usedUp, to: item) } label: {
                                    Label("Used Up", systemImage: "checkmark.circle")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button { apply(.tossed, to: item) } label: {
                                    Label("Tossed", systemImage: "xmark.bin")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }

                if !runningLow.isEmpty {
                    Section {
                        ForEach(runningLow) { entry in
                            ForecastRow(entry: entry, isOnList: onList.contains(entry.productID)) {
                                addToList(entry)
                            }
                        }
                    } header: {
                        Text("Running low soon")
                    } footer: {
                        Text("Predicted from how often you buy and use each item.")
                    }
                }

                if !outOfStock.isEmpty {
                    Section("Probably out") {
                        ForEach(outOfStock) { entry in
                            ForecastRow(entry: entry, isOnList: onList.contains(entry.productID)) {
                                addToList(entry)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Soon")
            .navigationDestination(for: InventoryItem.self) { item in
                ItemDetailView(item: item)
            }
            .toolbar {
                Menu {
                    Picker("Look ahead", selection: $horizonDays) {
                        Text("3 days").tag(3)
                        Text("1 week").tag(7)
                        Text("2 weeks").tag(14)
                    }
                } label: {
                    Label("Look ahead", systemImage: "calendar")
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private func apply(_ action: QuickAction, to item: InventoryItem) {
        do {
            _ = try withAnimation { try store.apply(action, to: item) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addToList(_ entry: ProductForecast) {
        do {
            let product = try store.product(id: entry.productID)
            try store.addToShoppingList(
                name: entry.name,
                quantity: entry.forecast.typicalPurchaseQuantity,
                unit: entry.forecast.unit,
                reason: .predicted,
                product: product
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ForecastRow: View {
    let entry: ProductForecast
    let isOnList: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: entry.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ConfidenceBadge(confidence: entry.forecast.confidence)
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: isOnList ? "checkmark.circle.fill" : "cart.badge.plus")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(isOnList)
            .accessibilityLabel(isOnList ? "On shopping list" : "Add to shopping list")
        }
    }

    private var detail: String {
        let forecast = entry.forecast
        if forecast.isOutOfStock {
            return "Usually lasts \(Self.duration(forecast.typicalPurchaseQuantity / forecast.dailyRate))"
        }
        let days = forecast.daysUntilRunOut(from: Date())
        let remaining = forecast.unit.label(for: forecast.estimatedRemaining)
        return "~\(remaining) left · runs out \(Self.relative(days))"
    }

    static func relative(_ days: Double) -> String {
        switch days {
        case ..<1: "today"
        case ..<2: "tomorrow"
        default: "in \(Int(days.rounded())) days"
        }
    }

    static func duration(_ days: Double) -> String {
        guard days.isFinite else { return "—" }
        let rounded = Int(days.rounded())
        return rounded == 1 ? "1 day" : "\(rounded) days"
    }
}

/// Three bars showing forecast confidence.
struct ConfidenceBadge: View {
    let confidence: ForecastConfidence

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index <= confidence.rawValue ? color : Color.secondary.opacity(0.25))
                    .frame(width: 10, height: 4)
            }
            Text(confidence.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(confidence.displayName)
    }

    private var color: Color {
        switch confidence {
        case .low: .orange
        case .medium: .yellow
        case .high: .green
        }
    }
}

#Preview {
    SoonView()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
