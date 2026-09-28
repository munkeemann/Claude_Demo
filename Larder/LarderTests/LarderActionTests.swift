import Testing
@testable import Larder

@MainActor
struct LarderActionTests {
    @Test func lockScreenButtonOpensInventoryWithTheFlow() async throws {
        let router = AppRouter.shared
        router.selectedTab = .settings
        defer { router.pendingAction = nil }

        _ = try await OpenLarderIntent(action: .tossOut).perform()

        #expect(router.selectedTab == .inventory)
        #expect(router.pendingAction == .tossOut)
    }

    @Test func everyActionHasItsOwnLabel() {
        let titles = Set(LarderAction.allCases.map(\.title))
        let symbols = Set(LarderAction.allCases.map(\.systemImage))
        #expect(titles.count == LarderAction.allCases.count)
        #expect(symbols.count == LarderAction.allCases.count)
        #expect(LarderAction.caseDisplayRepresentations.count == LarderAction.allCases.count)
    }
}
