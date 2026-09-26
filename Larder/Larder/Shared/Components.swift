import InventoryCore
import SwiftUI

extension ProductCategory {
    /// Earthy tones that sit with the icon's greens and honey.
    var tint: Color {
        switch self {
        case .produce: Color(hex: 0x5E9E5A)
        case .meat: Color(hex: 0xB5523B)
        case .seafood: Color(hex: 0x3F8C8C)
        case .dairy, .cheese, .eggs: Color(hex: 0xD49A36)
        case .bakery, .grains: Color(hex: 0xA77B4B)
        case .deli, .leftovers: Color(hex: 0xD4834A)
        case .frozen: Color(hex: 0x5E9CB8)
        case .canned, .condiments, .spices: Color(hex: 0x8C6A45)
        case .snacks: Color(hex: 0xC66B7E)
        case .beverages: Color(hex: 0x4FA38A)
        case .cleaning, .laundry: Color(hex: 0x4F7FA8)
        case .paperGoods, .other: Color(hex: 0x8A8578)
        case .personalCare, .health, .baby: Color(hex: 0x8A6FB0)
        case .pet: Color(hex: 0xC0522F)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
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
        case .expired, .today: Theme.terracotta
        case .soon: Theme.honeyInk
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
        case .inStock: Theme.green
        case .low: Theme.honeyInk
        case .usedUp: .secondary
        case .discarded: Theme.terracotta
        }
    }
}

/// A small capsule label, e.g. "Probably finished" or "Estimated".
struct TagBadge: View {
    let text: String
    var color: Color = Theme.honeyInk
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(color)
        .background(color.opacity(0.15), in: Capsule())
    }
}

/// Horizontally scrolling filter chip.
struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

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
            .foregroundStyle(textColor)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.green.opacity(isSelected ? 0 : 0.25)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // A selected chip is green on a cream page and cream on a green one.
    private var textColor: Color {
        guard isSelected else { return Theme.greenDeep }
        return colorScheme == .dark ? Theme.labelGreen : Theme.cream
    }

    private var fill: AnyShapeStyle {
        guard isSelected else { return AnyShapeStyle(Theme.card) }
        return colorScheme == .dark ? AnyShapeStyle(Theme.cream) : AnyShapeStyle(Theme.brandGradient)
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
