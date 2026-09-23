import InventoryCore
import SwiftUI

struct InventoryItemRow: View {
    let item: InventoryItem

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
                if item.status != .inStock {
                    StatusBadge(status: item.status)
                }
                if let expiry = item.expiryDate, item.status.isActive {
                    ExpiryBadge(date: expiry)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [item.quantityLabel]
        if item.unit == .each, let size = item.product?.packageSizeText {
            parts[0] += " × \(size)"
        }
        if let brand = item.product?.brand {
            parts.append(brand)
        }
        return parts.joined(separator: " · ")
    }
}
