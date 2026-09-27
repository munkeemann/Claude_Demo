import SwiftUI

/// The ways to add items. Tapping + starts the one picked in Settings;
/// holding it shows them all. Personal: stored on this phone only.
enum AddMethod: String, CaseIterable, Identifiable {
    case quickAdd
    case shelf
    case barcodes
    case receipt
    case manual

    static let `default`: AddMethod = .quickAdd

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quickAdd: "Quick Add"
        case .shelf: "Scan a Shelf"
        case .barcodes: "Scan Barcodes"
        case .receipt: "Scan a Receipt"
        case .manual: "Add One Item"
        }
    }

    var summary: String {
        switch self {
        case .quickAdd: "Type or say a list of things"
        case .shelf: "Photograph shelves or the fridge"
        case .barcodes: "Scan package after package"
        case .receipt: "Photograph a receipt"
        case .manual: "Fill in every detail"
        }
    }

    var systemImage: String {
        switch self {
        case .quickAdd: "text.badge.plus"
        case .shelf: "camera.viewfinder"
        case .barcodes: "barcode.viewfinder"
        case .receipt: "doc.text.viewfinder"
        case .manual: "square.and.pencil"
        }
    }
}

enum AddPreferences {
    static let defaultMethodKey = "add.defaultMethod"

    static var defaultMethod: AddMethod {
        UserDefaults.standard.string(forKey: defaultMethodKey).flatMap(AddMethod.init(rawValue:)) ?? .default
    }
}
