import SwiftUI
import WidgetKit

/// Larder's controls and widgets. Needs iOS 18, where apps can add their
/// own Lock Screen and Control Center buttons.
@main
struct LarderWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LarderActionControl()
    }
}
