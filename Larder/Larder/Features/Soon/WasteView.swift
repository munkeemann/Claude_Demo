import InventoryCore
import SwiftUI

/// This month's waste in one row, for the Soon tab.
struct WasteSummaryRow: View {
    let month: WasteReport.Month?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.bin")
                .font(.title3)
                .foregroundStyle(Theme.terracotta)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var headline: String {
        guard let month, month.tossedCount > 0 else { return "Nothing thrown out this month" }
        let items = month.tossedCount == 1 ? "1 item" : "\(month.tossedCount) items"
        guard month.tossedCents > 0 else { return "Tossed \(items) this month" }
        return "Tossed \(items), about \(WasteView.money(month.tossedCents)), this month"
    }

    private var detail: String {
        guard let month else { return "" }
        if let top = month.topCategories.first, month.tossedCount > 0 {
            return "Mostly \(top.category.displayName.lowercased()) · see past months"
        }
        return month.usedUpCount > 0 ? "\(month.usedUpCount) finished instead of tossed" : "See past months"
    }
}

/// Month by month: what was thrown out and roughly what it cost.
struct WasteView: View {
    let report: WasteReport

    var body: some View {
        List {
            ForEach(report.months) { month in
                Section {
                    if month.tossedCount == 0 {
                        Text(month.usedUpCount > 0 ? "Nothing thrown out; \(month.usedUpCount) finished." : "Nothing recorded.")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            stat("\(month.tossedCount)", "tossed")
                            stat(month.tossedCents > 0 ? Self.money(month.tossedCents) + (month.hasUnpricedItems ? "+" : "") : "—", "wasted")
                            stat(month.wasteShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", "of finished items")
                        }
                        .padding(.vertical, 4)
                        ForEach(month.tossed) { tossed in
                            HStack {
                                CategoryIcon(category: tossed.category, size: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tossed.name)
                                    Text("\(tossed.unit.label(for: tossed.quantity)) · \(tossed.date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let cents = tossed.costCents {
                                    Text(Self.money(cents))
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text(month.start.formatted(.dateTime.month(.wide).year()))
                }
            }
            Section {
            } footer: {
                Text("Costs come from receipt prices, so items without one aren't counted (a \"+\" means some are missing). Tossed items don't count toward how fast you use things.")
            }
        }
        .themedBackground()
        .navigationTitle("Food Waste")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.heading)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    static func money(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
    }
}
