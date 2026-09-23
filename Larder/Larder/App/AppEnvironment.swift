import Foundation
import InventoryCore
import Observation

/// Owns the app's service implementations. Views read it from the SwiftUI
/// environment; previews and tests inject stubs.
@Observable
@MainActor
final class AppEnvironment {
    let productLookup: any ProductLookupService
    let llm: any LLMService
    let secrets: any SecretStore
    /// Canned LLM used for the offline sample-receipt demo.
    let demoLLM: any LLMService

    /// Bumped when the API key changes so views re-read `hasAPIKey`.
    private(set) var apiKeyRevision = 0

    init(
        productLookup: any ProductLookupService,
        llm: any LLMService,
        secrets: any SecretStore,
        demoLLM: any LLMService = MockLLMService(delay: 1.5)
    ) {
        self.productLookup = productLookup
        self.llm = llm
        self.secrets = secrets
        self.demoLLM = demoLLM
    }

    static func live() -> AppEnvironment {
        let secrets = KeychainSecretStore()
        let client = AnthropicClient(apiKey: { try secrets.secret(for: SecretKey.anthropicAPIKey) })
        return AppEnvironment(
            productLookup: OpenFactsClient(userAgent: userAgent),
            llm: AnthropicLLMService(client: client, model: { ModelPreference.current }),
            secrets: secrets
        )
    }

    static func preview() -> AppEnvironment {
        AppEnvironment(
            productLookup: PreviewProductLookup(),
            llm: MockLLMService(delay: 1),
            secrets: InMemorySecretStore([SecretKey.anthropicAPIKey: "sk-ant-preview"])
        )
    }

    // MARK: - API key

    var hasAPIKey: Bool {
        _ = apiKeyRevision
        let key = (try? secrets.secret(for: SecretKey.anthropicAPIKey)) ?? nil
        return !(key ?? "").isEmpty
    }

    func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try secrets.setSecret(trimmed, for: SecretKey.anthropicAPIKey)
        apiKeyRevision += 1
    }

    func removeAPIKey() throws {
        try secrets.removeSecret(for: SecretKey.anthropicAPIKey)
        apiKeyRevision += 1
    }

    /// Open Food Facts asks clients to identify themselves.
    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "Larder-iOS/\(version) (personal household inventory app)"
    }
}

/// The Claude model chosen in Settings. Not secret, so UserDefaults is fine.
enum ModelPreference {
    static let key = "claude.model"

    static var current: ClaudeModel {
        UserDefaults.standard.string(forKey: key).flatMap(ClaudeModel.init(rawValue:)) ?? .default
    }
}

/// Offline lookup used by previews: knows a single barcode.
struct PreviewProductLookup: ProductLookupService {
    func lookup(barcode: String) async throws -> ProductLookupResult? {
        guard TextNormalizer.barcode(barcode) == "0076808280593" else { return nil }
        return ProductLookupResult(
            barcode: "0076808280593",
            name: "Spaghetti",
            brand: "Barilla",
            category: .grains,
            packageSize: PackageSize(count: 1, unitSize: Quantity(16, .ounce)),
            packageSizeText: "16 oz",
            source: .food
        )
    }
}
