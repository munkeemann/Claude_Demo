import InventoryCore
import Testing
@testable import Larder

struct SmokeTests {
    @Test func coreModuleIsLinked() {
        #expect(!InventoryCore.version.isEmpty)
        #expect(!ProductCategory.allCases.isEmpty)
    }

    @Test func appVersionIsReadable() {
        #expect(!SettingsView.appVersion.isEmpty)
    }
}
