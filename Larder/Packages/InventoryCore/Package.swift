// swift-tools-version: 6.0
import PackageDescription

// InventoryCore holds every piece of Larder's logic that can be expressed in
// plain Swift + Foundation: domain types, forecasting, receipt/recipe parsing,
// and the HTTP clients. It must not import SwiftUI, SwiftData, UIKit, Vision, or
// any other Apple-only framework so that `swift test` runs on macOS and Linux.
let package = Package(
    name: "InventoryCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "InventoryCore", targets: ["InventoryCore"]),
    ],
    targets: [
        .target(name: "InventoryCore"),
        .testTarget(name: "InventoryCoreTests", dependencies: ["InventoryCore"]),
    ]
)
