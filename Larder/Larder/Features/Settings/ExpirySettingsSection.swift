import InventoryCore
import SwiftData
import SwiftUI

/// How you add things. Personal: each phone keeps its own.
struct AddingSettingsSection: View {
    @AppStorage(AddPreferences.defaultMethodKey) private var defaultMethodRaw = AddMethod.default.rawValue
    @AppStorage(ExpiryPreferences.modeKey) private var expiryModeRaw = ExpiryEntryMode.estimate.rawValue

    var body: some View {
        Section {
            Picker(selection: $defaultMethodRaw) {
                ForEach(AddMethod.allCases) { method in
                    Label(method.label, systemImage: method.systemImage).tag(method.rawValue)
                }
            } label: {
                Text("Tapping + opens")
            }
            Picker("Expiry dates", selection: $expiryModeRaw) {
                ForEach(ExpiryEntryMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
        } header: {
            Text("Adding items")
        } footer: {
            Text("Hold + for the other ways to add. \((ExpiryEntryMode(rawValue: expiryModeRaw) ?? .estimate).summary) These are just for you.")
        }
    }
}

/// How strictly the whole home reads dates.
struct ExpirySettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [HouseholdSettings]

    private var strictness: ExpiryStrictness { settings.first?.expiryStrictness ?? .default }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("How cautious?")
                    Spacer()
                    Text(strictness.label)
                        .foregroundStyle(Theme.green)
                        .fontWeight(.semibold)
                }
                Slider(
                    value: Binding(
                        get: { Double(strictness.rawValue) },
                        set: { set(ExpiryStrictness(rawValue: Int($0.rounded())) ?? .default) }
                    ),
                    in: 0...Double(ExpiryStrictness.allCases.count - 1),
                    step: 1
                ) {
                    Text("How cautious")
                } minimumValueLabel: {
                    Image(systemName: "shield.lefthalf.filled")
                        .accessibilityLabel("Cautious")
                } maximumValueLabel: {
                    Image(systemName: "leaf")
                        .accessibilityLabel("Relaxed")
                }
                .tint(Theme.green)
                Text(strictness.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(examples, id: \.self) { example in
                        Label(example, systemImage: "circle.fill")
                            .labelStyle(BulletLabelStyle())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Expiration dates")
        } footer: {
            Text("Shared with everyone in your home. Meat, poultry, seafood, deli, dairy, leftovers and baby food never go past USDA's longest storage time, however relaxed you set this. Storage times: USDA FoodKeeper.")
        }
    }

    /// What the setting means for a few everyday foods.
    private var examples: [String] {
        let grace = ExpiryCalculator.printedDateGrace(category: .canned, strictness: strictness)
        let canned = grace == 0
            ? "Canned beans: toss on their best-by date"
            : "Canned beans: keep about \(ExpiryCalculator.describe(grace...grace)) past their best-by date"
        var lines = [canned]
        if let yogurt = FoodKeeper.entry(id: 33)?.unopened(.fridge)?.range {
            let days = ExpiryCalculator.compute(
                ExpiryInputs(category: .dairy, foodKeeper: FoodKeeper.entry(id: 33), climate: .fridge, purchaseDate: Date()),
                strictness: strictness
            ).date.map { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: $0)).day ?? 0 }
            if let days { lines.append("Yogurt: \(days) days after buying (USDA: \(ExpiryCalculator.describe(yogurt)))") }
        }
        lines.append("Raw chicken: always within USDA's 1–2 days")
        return lines
    }

    private func set(_ value: ExpiryStrictness) {
        guard value != strictness else { return }
        try? InventoryStore(context: modelContext).setExpiryStrictness(value)
        let context = modelContext
        Task { await Reminders.refresh(context: context) }
    }
}

/// A small bullet instead of the icon.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            configuration.title
        }
    }
}
