import SwiftUI

struct RootView: View {
    enum Tab: Hashable {
        case inventory
        case settings
    }

    @State private var selection: Tab = .inventory

    var body: some View {
        TabView(selection: $selection) {
            InventoryHomeView()
                .tabItem { Label("Inventory", systemImage: "cabinet") }
                .tag(Tab.inventory)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
