import AppIntents

/// Something to jump straight into from outside the app: a Lock Screen or
/// Control Center button, the Action button, Siri or Shortcuts. The widget
/// extension compiles this file too, so it only uses system frameworks.
enum LarderAction: String, AppEnum {
    case add
    case barcodes
    case shelf
    case receipt
    case quickAdd
    case tossOut
    case useUp
    case recipe

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Larder Action"

    // Literal text: the App Intents build step reads these at compile time.
    static let caseDisplayRepresentations: [LarderAction: DisplayRepresentation] = [
        .add: DisplayRepresentation(title: "Add Items", subtitle: "Your usual way of adding, from Settings", image: .init(systemName: "plus.viewfinder")),
        .barcodes: DisplayRepresentation(title: "Scan Barcodes", subtitle: "Scan package after package", image: .init(systemName: "barcode.viewfinder")),
        .shelf: DisplayRepresentation(title: "Scan a Shelf", subtitle: "Photograph shelves or the fridge", image: .init(systemName: "camera.viewfinder")),
        .receipt: DisplayRepresentation(title: "Scan a Receipt", subtitle: "Photograph a receipt", image: .init(systemName: "doc.text.viewfinder")),
        .quickAdd: DisplayRepresentation(title: "Quick Add", subtitle: "Type or say a list", image: .init(systemName: "text.badge.plus")),
        .tossOut: DisplayRepresentation(title: "Toss Things Out", subtitle: "Photograph what you're throwing away", image: .init(systemName: "xmark.bin")),
        .useUp: DisplayRepresentation(title: "Used Things Up", subtitle: "Photograph what you finished", image: .init(systemName: "checkmark.circle")),
        .recipe: DisplayRepresentation(title: "I Cooked a Recipe", subtitle: "Photograph the recipe you made", image: .init(systemName: "frying.pan")),
    ]

    /// The button's label in Control Center.
    var title: String {
        switch self {
        case .add: "Add Items"
        case .barcodes: "Scan Barcodes"
        case .shelf: "Scan a Shelf"
        case .receipt: "Scan a Receipt"
        case .quickAdd: "Quick Add"
        case .tossOut: "Toss Things Out"
        case .useUp: "Used Things Up"
        case .recipe: "I Cooked a Recipe"
        }
    }

    var systemImage: String {
        switch self {
        case .add: "plus.viewfinder"
        case .barcodes: "barcode.viewfinder"
        case .shelf: "camera.viewfinder"
        case .receipt: "doc.text.viewfinder"
        case .quickAdd: "text.badge.plus"
        case .tossOut: "xmark.bin"
        case .useUp: "checkmark.circle"
        case .recipe: "frying.pan"
        }
    }
}

/// Opens Larder on the Inventory tab with the chosen flow showing. The
/// widget extension's Lock Screen button runs it; because it opens the app,
/// iOS performs it in the app, where it hands the action to `AppRouter`.
struct OpenLarderIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan In or Out"
    static let description = IntentDescription("Opens Larder straight to scanning things in or out.")
    static let openAppWhenRun = true

    @Parameter(title: "Action", default: .add)
    var action: LarderAction

    init() {}

    init(action: LarderAction) {
        self.action = action
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        AppRouter.shared.open(action)
        #endif
        return .result()
    }
}
