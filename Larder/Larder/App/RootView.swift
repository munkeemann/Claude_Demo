import CloudKit
import SwiftUI

struct RootView: View {
    enum Tab: Hashable {
        case inventory
        case soon
        case recipes
        case shopping
        case settings
    }

    private var homeSync: HomeSync { .shared }

    var body: some View {
        @Bindable var router = AppRouter.shared
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
        .sheet(isPresented: Binding(
            get: { homeSync.pendingInvitation != nil },
            set: { if !$0 { homeSync.pendingInvitation = nil } }
        )) {
            if let metadata = homeSync.pendingInvitation {
                JoinHomeView(metadata: metadata)
                    .tint(Theme.green)
                    .fontDesign(.rounded)
            }
        }
        .alert(
            "Household",
            isPresented: Binding(get: { homeSync.notice != nil }, set: { if !$0 { homeSync.notice = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(homeSync.notice ?? "")
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
