import InventoryCore
import SwiftUI

struct InventoryItemRow: View {
    let item: InventoryItem
    /// The forecast's projection for this item, when its product tracks
    /// run-out and has history.
    var estimate: ItemEstimate?

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: item.product?.category ?? .other)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if isProbablyFinished {
                    TagBadge(text: "Finished?", systemImage: "questionmark")
                } else if item.status != .inStock {
                    StatusBadge(status: item.status)
                } else if isEstimatedLow {
                    TagBadge(text: "Low", systemImage: "chart.line.downtrend.xyaxis")
                }
                if let expiry = item.expiryDate, item.status.isActive {
                    ExpiryBadge(date: expiry)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var activeEstimate: ItemEstimate? {
        guard item.status.isActive, let estimate, estimate.isProjected else { return nil }
        return estimate
    }

    private var isProbablyFinished: Bool { activeEstimate?.isProbablyFinished ?? false }

    private var isEstimatedLow: Bool {
        guard let estimate = activeEstimate, item.initialQuantity > 0 else { return false }
        return estimate.remaining <= item.initialQuantity * QuickActionCalculator.lowFraction
    }

    private var quantityText: String {
        if isProbablyFinished { return "Probably used up" }
        if let estimate = activeEstimate {
            return "~\(item.unit.label(for: estimate.roundedRemaining)) left"
        }
        return item.quantityLabel
    }

    private var subtitle: String {
        var parts = [quantityText]
        if item.unit == .each, activeEstimate == nil, let size = item.product?.packageSizeText {
            parts[0] += " × \(size)"
        }
        if let brand = item.product?.brand {
            parts.append(brand)
        }
        return parts.joined(separator: " · ")
    }
}
