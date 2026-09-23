import Foundation

/// Every LLM feature goes through this protocol, so the direct Anthropic
/// implementation can later be swapped for a backend proxy without touching
/// callers.
public protocol LLMService: Sendable {
    /// Extracts structured line items from receipt OCR text.
    func extractReceipt(_ input: ReceiptExtractionInput) async throws -> ReceiptExtraction

    /// Suggests recipes that use the given inventory.
    func suggestRecipes(_ request: RecipeRequest) async throws -> [Recipe]

    /// Confirms the service is usable (for example, that the API key works).
    func verify() async throws
}

/// Calls the Anthropic Messages API directly with the user's own key.
public struct AnthropicLLMService: LLMService {
    private let client: AnthropicClient
    private let model: @Sendable () -> ClaudeModel

    /// - Parameter model: Read per request so a Settings change applies immediately.
    public init(client: AnthropicClient, model: @escaping @Sendable () -> ClaudeModel) {
        self.client = client
        self.model = model
    }

    public func extractReceipt(_ input: ReceiptExtractionInput) async throws -> ReceiptExtraction {
        guard !input.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ReceiptExtraction(items: [])
        }
        return try await client.structuredOutput(
            ReceiptExtraction.self,
            model: model(),
            system: ReceiptPrompt.system,
            user: ReceiptPrompt.userMessage(for: input),
            schema: ReceiptExtractionSchema.schema
        )
    }

    public func suggestRecipes(_ request: RecipeRequest) async throws -> [Recipe] {
        guard !request.items.isEmpty else { return [] }
        let response = try await client.structuredOutput(
            RecipeResponse.self,
            model: model(),
            system: RecipePrompt.system,
            user: RecipePrompt.userMessage(for: request),
            schema: RecipePrompt.schema
        )
        return response.recipes
    }

    public func verify() async throws {
        try await client.verify(model: model())
    }
}

/// Canned responses for previews, tests, and the offline demo.
public struct MockLLMService: LLMService {
    public var receipt: ReceiptExtraction
    public var recipes: [Recipe]
    public var delay: TimeInterval

    public init(
        receipt: ReceiptExtraction = SampleReceipt.extraction,
        recipes: [Recipe] = SampleRecipes.recipes,
        delay: TimeInterval = 0
    ) {
        self.receipt = receipt
        self.recipes = recipes
        self.delay = delay
    }

    public func extractReceipt(_ input: ReceiptExtractionInput) async throws -> ReceiptExtraction {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return receipt
    }

    public func suggestRecipes(_ request: RecipeRequest) async throws -> [Recipe] {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return recipes
    }

    public func verify() async throws {}
}
