import AppIntents
import SwiftUI
import WidgetKit

/// A button for the Lock Screen, Control Center or the Action button that
/// opens Larder straight to a scanner. Each button is set to one action
/// when it's added: Scan Barcodes in one corner and Toss Things Out in the
/// other, say.
struct LarderActionControl: ControlWidget {
    static let kind = "com.munkeemann.larder.action"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, intent: LarderControlConfiguration.self) { configuration in
            ControlWidgetButton(action: OpenLarderIntent(action: configuration.action)) {
                Label(configuration.action.title, systemImage: configuration.action.systemImage)
            }
        }
        .displayName("Larder")
        .description("Opens Larder straight to scanning things in or out.")
        .promptsForUserConfiguration()
    }
}

/// What a Larder button opens, picked when it's added.
struct LarderControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Larder Button"
    static let description = IntentDescription("Pick what this button opens.")

    @Parameter(title: "Opens", default: .add)
    var action: LarderAction

    func perform() async throws -> some IntentResult {
        .result()
    }
}
