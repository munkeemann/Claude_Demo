import SwiftUI
import UIKit

/// Colors and styling taken from the app icon: a green jar label, a cream
/// jar and a honey lid. Every color has a dark-mode variant in the asset
/// catalog. In light mode pages are cream; in dark mode they're the icon's
/// green, with cream text and dark cards.
enum Theme {
    static let green = Color.accentColor
    /// The jar label's deep green. Emphasis text on cards.
    static let greenDeep = Color("LarderGreenDeep")
    /// Titles and headings that sit on the page: deep green on cream, cream
    /// on the dark-mode green.
    static let heading = Color("LarderHeading")
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
    /// The jar label's deep green in both modes, for text on cream.
    static let labelGreen = Color(red: 0.161, green: 0.361, blue: 0.196)

    /// Navigation titles in the heading color, set in the rounded face the
    /// rest of the app uses.
    @MainActor
    static func applyAppearance() {
        let titleColor = UIColor(named: "LarderHeading") ?? .label
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
    /// The page background behind lists and forms: cream, or the icon's
    /// green in dark mode.
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }
}

private struct ThemedBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let page = content
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
        if colorScheme == .dark {
            // System gray section headers and footers are hard to read on
            // the green, so text defaults to cream (rows stay dark cards).
            page.foregroundStyle(Theme.cream, Theme.cream.opacity(0.88))
        } else {
            page
        }
    }
}

/// A rounded card on the brand gradient, like the icon. In dark mode the
/// page is already that green, so the card is dark instead.
struct BrandCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(Theme.cream)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var fill: AnyShapeStyle {
        colorScheme == .dark ? AnyShapeStyle(Theme.card) : AnyShapeStyle(Theme.brandGradient)
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
