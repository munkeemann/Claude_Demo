import SwiftUI

struct RootView: View {
    enum Tab: Hashable {
        case inventory
        case soon
        case recipes
        case shopping
        case settings
    }

    @Bindable private var router = AppRouter.shared

    var body: some View {
        TabView(selection: $router.selectedTab) {
            InventoryHomeView()
                .tabItem { Label("Inventory", systemImage: "cabinet") }
                .tag(Tab.inventory)

            SoonView()
                .tabItem { Label("Soon", systemImage: "clock.badge.exclamationmark") }
                .tag(Tab.soon)

            RecipesView()
                .tabItem { Label("Recipes", systemImage: "fork.knife") }
                .tag(Tab.recipes)

            ShoppingListView()
                .tabItem { Label("Shopping", systemImage: "cart") }
                .tag(Tab.shopping)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Theme.green)
        .fontDesign(.rounded)
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
