import SwiftUI

struct InventoryHomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Nothing tracked yet",
                systemImage: "cabinet",
                description: Text("Items you add, scan, or import from receipts will show up here.")
            )
            .navigationTitle("Inventory")
        }
    }
}

#Preview {
    InventoryHomeView()
}
