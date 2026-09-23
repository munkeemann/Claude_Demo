import InventoryCore
import SwiftUI

extension ProductCategory {
    var tint: Color {
        switch self {
        case .produce: .green
        case .meat: .red
        case .seafood: .teal
        case .dairy, .cheese, .eggs: .yellow
        case .bakery, .grains: .brown
        case .deli, .leftovers: .orange
        case .frozen: .cyan
        case .canned, .condiments, .spices: .indigo
        case .snacks: .pink
        case .beverages: .mint
        case .cleaning, .laundry: .blue
        case .paperGoods, .other: .gray
        case .personalCare, .health, .baby: .purple
        case .pet: .orange
        }
    }
}

/// Rounded, tinted SF Symbol for a category.
struct CategoryIcon: View {
    let category: ProductCategory
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// "Tomorrow", "3 days", "Expired" with a color that reflects urgency.
struct ExpiryBadge: View {
    let date: Date
    var now: Date = Date()

    var body: some View {
        let status = ExpiryStatus(expiry: date, now: now)
        Text(status.shortLabel)
            .font(.caption.weight(.medium))
            .foregroundStyle(color(for: status.urgency))
            .accessibilityLabel("Expiry: \(status.shortLabel)")
    }

    private func color(for urgency: ExpiryStatus.Urgency) -> Color {
        switch urgency {
        case .expired, .today: .red
        case .soon: .orange
        case .later: .secondary
        }
    }
}

struct StatusBadge: View {
    let status: ItemStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(foreground.opacity(0.15), in: Capsule())
    }

    private var foreground: Color {
        switch status {
        case .inStock: .green
        case .low: .orange
        case .usedUp: .secondary
        case .discarded: .red
        }
    }
}

/// Horizontally scrolling filter chip.
struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    /// Presents `message` in an alert and clears it on dismiss.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

extension Int {
    /// Formats minor units (cents) as currency.
    func formattedCents(currencyCode: String) -> String {
        (Double(self) / 100).formatted(.currency(code: currencyCode))
    }
}
