import AppIntents
import Foundation
import InventoryCore
import SwiftData

/// "Hey Siri, add to Larder" → "What did you get?" → "Milk, eggs and bread."
/// The list is read on the phone (no Claude call), and each item goes
/// where it's usually kept.
struct AddToLarderIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Larder"
    static let description = IntentDescription("Adds things you just got, like \"milk, a dozen eggs and bread\".")

    @Parameter(title: "Items", requestValueDialog: "What did you get?")
    var items: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppContainer.shared.mainContext
        let store = InventoryStore(context: context)
        let parsed = QuickAddParser.parse(items, knownBrands: (try? store.knownBrands()) ?? [])
        guard !parsed.isEmpty else {
            return .result(dialog: "I didn't catch any items.")
        }
        let lines = try store.quickAddLines(parsed)
        let added = try store.importShelfScan(ShelfScanReview(lines: lines, locationID: nil, source: .manual, justBought: true))
        await Reminders.refresh(context: context)
        let names = ListFormatter.localizedString(byJoining: added.map(\.displayName))
        return .result(dialog: "Added \(names) to Larder.")
    }
}

/// "Hey Siri, we finished something in Larder" → "What did you use up?"
struct UsedUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Used Something Up"
    static let description = IntentDescription("Marks an item as used up.")

    @Parameter(title: "Item", requestValueDialog: "What did you use up?")
    var item: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.finish(item, with: .usedUp, verb: "used up")
    }
}

/// "Hey Siri, toss something in Larder" → "What did you throw out?"
struct TossedIntent: AppIntent {
    static let title: LocalizedStringResource = "Tossed Something"
    static let description = IntentDescription("Marks an item as thrown out.")

    @Parameter(title: "Item", requestValueDialog: "What did you throw out?")
    var item: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentSupport.finish(item, with: .tossed, verb: "tossed")
    }
}

/// "Hey Siri, what's expiring in Larder?"
struct WhatsExpiringIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Expiring"
    static let description = IntentDescription("Lists what to use up in the next few days.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let items = try ForecastService(context: AppContainer.shared.mainContext).expiringItems(withinDays: 3)
        guard !items.isEmpty else {
            return .result(dialog: "Nothing expires in the next three days.")
        }
        let names = ListFormatter.localizedString(byJoining: items.prefix(6).map(\.displayName))
        let more = items.count > 6 ? ", and \(items.count - 6) more" : ""
        return .result(dialog: "Use up \(names)\(more) in the next few days.")
    }
}

struct LarderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddToLarderIntent(),
            phrases: ["Add to \(.applicationName)", "Add groceries to \(.applicationName)"],
            shortTitle: "Add to Larder",
            systemImageName: "text.badge.plus"
        )
        AppShortcut(
            intent: UsedUpIntent(),
            phrases: ["Used something up in \(.applicationName)", "We finished something in \(.applicationName)"],
            shortTitle: "Used Up",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: TossedIntent(),
            phrases: ["Toss something in \(.applicationName)", "Threw something out in \(.applicationName)"],
            shortTitle: "Tossed",
            systemImageName: "xmark.bin"
        )
        AppShortcut(
            intent: OpenLarderIntent(),
            phrases: ["\(\.$action) in \(.applicationName)", "Open \(.applicationName) to \(\.$action)"],
            shortTitle: "Scan In or Out",
            systemImageName: "barcode.viewfinder"
        )
        AppShortcut(
            intent: WhatsExpiringIntent(),
            phrases: ["What's expiring in \(.applicationName)", "What should I use up in \(.applicationName)"],
            shortTitle: "What's Expiring",
            systemImageName: "clock.badge.exclamationmark"
        )
    }
}

@MainActor
enum IntentSupport {
    /// Finds the in-stock item a spoken name means (soonest-expiring first)
    /// and applies the action.
    static func finish(_ spoken: String, with action: QuickAction, verb: String) async throws -> some IntentResult & ProvidesDialog {
        let context = AppContainer.shared.mainContext
        let store = InventoryStore(context: context)
        let key = TextNormalizer.key(spoken)
        let match = try store.activeItems().first { item in
            let name = TextNormalizer.key(item.displayName)
            return !key.isEmpty && (name == key || name.contains(key) || key.contains(name))
        }
        guard let match else {
            return .result(dialog: "I couldn't find \(spoken) in Larder.")
        }
        try store.apply(action, to: match)
        await Reminders.refresh(context: context)
        return .result(dialog: "Marked \(match.displayName) as \(verb).")
    }
}
