import InventoryCore
import SwiftData
import SwiftUI

struct RecipeDetailView: View {
    let evaluated: EvaluatedRecipe

    @Environment(\.modelContext) private var modelContext
    @State private var isFavorite = false
    @State private var addedMissing = false
    @State private var isShowingCooked = false
    @State private var cookedMessage: String?
    @State private var errorMessage: String?

    private var recipe: Recipe { evaluated.recipe }
    private var store: InventoryStore { InventoryStore(context: modelContext) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if !recipe.summary.isEmpty {
                        Text(recipe.summary)
                    }
                    HStack(spacing: 14) {
                        Label(recipe.mealType.displayName, systemImage: "fork.knife")
                        if recipe.totalMinutes > 0 {
                            Label("\(recipe.totalMinutes) min", systemImage: "clock")
                        }
                        Label("Serves \(recipe.servings)", systemImage: "person.2")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if !evaluated.expiringItemNames.isEmpty {
                        Label("Uses soon-to-expire \(evaluated.expiringItemNames.joined(separator: ", "))", systemImage: "leaf")
                            .font(.callout)
                            .foregroundStyle(Theme.green)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(Array(evaluated.ingredients.enumerated()), id: \.offset) { _, ingredient in
                    IngredientRow(ingredient: ingredient, itemName: itemName(for: ingredient))
                }
                if evaluated.missingCount > 0 {
                    Button {
                        addMissing()
                    } label: {
                        Label(
                            addedMissing
                                ? "Added to shopping list"
                                : "Add \(evaluated.missingCount) missing to shopping list",
                            systemImage: addedMissing ? "checkmark" : "cart.badge.plus"
                        )
                    }
                    .disabled(addedMissing)
                }
            } header: {
                Text("Ingredients")
            }

            if !recipe.steps.isEmpty {
                Section("Steps") {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                            Text(step)
                        }
                    }
                }
            }

            Section {
                Button {
                    isShowingCooked = true
                } label: {
                    Label("I cooked this", systemImage: "frying.pan")
                }
                .disabled(evaluated.usedItemIDs.isEmpty)
            } footer: {
                if let cookedMessage {
                    Text(cookedMessage)
                } else {
                    Text("Logs what you used so your inventory and forecasts stay accurate.")
                }
            }
        }
        .themedBackground()
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                toggleFavorite()
            } label: {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "heart.fill" : "heart")
            }
            .tint(Theme.terracotta)
        }
        .sheet(isPresented: $isShowingCooked) {
            CookedSheet(evaluated: evaluated) { count in
                cookedMessage = count == 1 ? "Logged 1 ingredient." : "Logged \(count) ingredients."
            }
        }
        .onAppear {
            isFavorite = (try? store.isFavorite(recipe)) ?? false
        }
        .errorAlert($errorMessage)
    }

    private func itemName(for ingredient: EvaluatedIngredient) -> String? {
        guard let id = ingredient.itemID else { return nil }
        return (try? store.item(id: id))?.displayName
    }

    private func addMissing() {
        do {
            try store.addMissingIngredients(of: evaluated)
            addedMissing = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFavorite() {
        do {
            try store.setFavorite(recipe, !isFavorite)
            isFavorite.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct IngredientRow: View {
    let ingredient: EvaluatedIngredient
    let itemName: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.ingredient.name.capitalized)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(ingredient.ingredient.amount)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch ingredient.availability {
        case .inInventory:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
        case .staple:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        case .missing:
            Image(systemName: "cart").foregroundStyle(Theme.honeyInk)
        }
    }

    private var detail: String? {
        switch ingredient.availability {
        case .inInventory: itemName.map { "From your \($0)" }
        case .staple: "Pantry staple"
        case .missing: "Need to buy"
        }
    }
}

/// Confirms how much of each item was used, then logs usage.
struct CookedSheet: View {
    let evaluated: EvaluatedRecipe
    var onLogged: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var uses: [Use] = []
    @State private var errorMessage: String?

    struct Use: Identifiable {
        let item: InventoryItem
        var amount: Double
        var include: Bool
        var id: UUID { item.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($uses) { $use in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $use.include) {
                                VStack(alignment: .leading) {
                                    Text(use.item.displayName)
                                    Text("\(use.item.quantityLabel) in stock")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if use.include {
                                Stepper(
                                    value: $use.amount,
                                    in: 0...max(use.item.quantity, 0.01),
                                    step: QuickActionCalculator.useStep(for: use.item.state)
                                ) {
                                    Text("Used \(use.item.unit.label(for: use.amount))")
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Amounts are estimated from the recipe. Adjust them to match what you actually used.")
                }
            }
            .themedBackground()
            .navigationTitle("What did you use?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { log() }
                        .disabled(!uses.contains { $0.include && $0.amount > 0 })
                }
            }
            .onAppear(perform: prepare)
            .errorAlert($errorMessage)
        }
    }

    /// One row per inventory item, summing ingredients that map to the same item.
    private func prepare() {
        guard uses.isEmpty else { return }
        let store = InventoryStore(context: modelContext)
        var byItem: [UUID: Use] = [:]
        var order: [UUID] = []
        for ingredient in evaluated.ingredients {
            guard let id = ingredient.itemID, let item = try? store.item(id: id), item.status.isActive else { continue }
            let amount = CookedUsagePlanner.suggestedAmount(recipeAmount: ingredient.ingredient.amount, item: item.state)
            if var existing = byItem[id] {
                existing.amount = min(item.quantity, existing.amount + amount)
                byItem[id] = existing
            } else {
                byItem[id] = Use(item: item, amount: amount, include: true)
                order.append(id)
            }
        }
        uses = order.compactMap { byItem[$0] }
    }

    private func log() {
        let selected = uses.filter { $0.include && $0.amount > 0 }
        do {
            try InventoryStore(context: modelContext).markCooked(
                evaluated.recipe,
                uses: selected.map { (item: $0.item, amount: $0.amount) }
            )
            onLogged(selected.count)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
