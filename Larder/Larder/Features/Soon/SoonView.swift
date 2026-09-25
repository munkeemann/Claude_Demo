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
    @State private var recountItem: InventoryItem?
    @State private var errorMessage: String?

    private var service: ForecastService { ForecastService(context: modelContext) }
    private var store: InventoryStore { InventoryStore(context: modelContext) }

    var body: some View {
        let expiring = (try? service.expiringItems(withinDays: horizonDays)) ?? []
        let snapshot = (try? service.snapshot()) ?? .empty
        let forecasts = snapshot.forecasts
        let finished = items
            .filter { $0.status.isActive && snapshot.estimates[$0.id]?.isProbablyFinished == true }
            .sorted { $0.purchaseDate < $1.purchaseDate }
        let horizon = Date().addingTimeInterval(Double(horizonDays) * 86_400)
        let runningLow = forecasts.filter { !$0.forecast.isOutOfStock && $0.forecast.runOutDate <= horizon }
        let outOfStock = forecasts.filter { $0.forecast.isOutOfStock && $0.purchaseCount >= 2 }
        let onList = Set(shoppingEntries.filter { !$0.isChecked }.compactMap { $0.product?.id })

        NavigationStack {
            List {
                if expiring.isEmpty && runningLow.isEmpty && outOfStock.isEmpty && finished.isEmpty {
                    ContentUnavailableView(
                        "Nothing urgent",
                        systemImage: "checkmark.seal",
                        description: Text("Nothing expires or runs out in the next \(horizonDays) days.")
                    )
                    .listRowBackground(Color.clear)
                }

                if !finished.isEmpty {
                    Section {
                        ForEach(finished) { item in
                            ProbablyFinishedRow(
                                item: item,
                                onFinished: { perform { try store.confirmFinished(item) } },
                                onStillHave: { recountItem = item }
                            )
                        }
                    } header: {
                        Text("Probably finished")
                    } footer: {
                        Text("Based on how fast you usually go through them. One tap keeps the forecast honest.")
                    }
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
                                .tint(Theme.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button { apply(.tossed, to: item) } label: {
                                    Label("Tossed", systemImage: "xmark.bin")
                                }
                                .tint(Theme.terracotta)
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
            .themedBackground()
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
            .sheet(item: $recountItem) { item in
                RecountSheet(item: item)
            }
            .errorAlert($errorMessage)
        }
    }

    private func apply(_ action: QuickAction, to item: InventoryItem) {
        perform { _ = try store.apply(action, to: item) }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try withAnimation { try work() }
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

/// An item the forecast thinks is gone: confirm or correct it in one tap.
private struct ProbablyFinishedRow: View {
    let item: InventoryItem
    let onFinished: () -> Void
    let onStillHave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: item.product?.category ?? .other)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                Text("Bought \(item.purchaseDate.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onFinished) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.green)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("It's finished")
            Button(action: onStillHave) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.title2)
                    .foregroundStyle(Theme.honeyInk)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Still have some")
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
        case .low: Theme.terracotta
        case .medium: Theme.honey
        case .high: Theme.green
        }
    }
}

#Preview {
    SoonView()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
