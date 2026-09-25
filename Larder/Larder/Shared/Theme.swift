import SwiftUI
import UIKit

/// Colors and styling taken from the app icon: a green jar label, a cream
/// jar and a honey lid. Every color has a dark-mode variant in the asset
/// catalog.
enum Theme {
    static let green = Color.accentColor
    /// The jar label's deep green. Titles and emphasis text.
    static let greenDeep = Color("LarderGreenDeep")
    static let background = Color("LarderBackground")
    static let card = Color("LarderCard")
    static let honey = Color("LarderHoney")
    /// Honey dark enough to read as text on light backgrounds.
    static let honeyInk = Color("LarderHoneyInk")
    static let terracotta = Color("LarderTerracotta")

    /// The icon's background gradient.
    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.227, green: 0.533, blue: 0.278), Color(red: 0.310, green: 0.608, blue: 0.322)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// Cream from the jar, for text on the brand gradient.
    static let cream = Color(red: 0.980, green: 0.953, blue: 0.878)

    /// Navigation titles in the label green, set in the rounded face the
    /// rest of the app uses.
    @MainActor
    static func applyAppearance() {
        let titleColor = UIColor(named: "LarderGreenDeep") ?? .label
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [
            .foregroundColor: titleColor,
            .font: UIFont.rounded(size: 34, weight: .bold),
        ]
        appearance.titleTextAttributes = [
            .foregroundColor: titleColor,
            .font: UIFont.rounded(size: 17, weight: .semibold),
        ]
    }
}

extension UIFont {
    static func rounded(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension View {
    /// Cream page background behind lists and forms.
    func themedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}

/// A rounded card on the brand gradient, like the icon.
struct BrandCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(Theme.cream)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// The jar from the app icon.
struct LarderMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image("LarderMark")
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .accessibilityHidden(true)
    }
}
