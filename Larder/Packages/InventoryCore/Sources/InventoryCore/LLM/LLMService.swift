import Foundation

/// Every LLM feature goes through this protocol, so the direct Anthropic
/// implementation can later be swapped for a backend proxy without touching
/// callers.
public protocol LLMService: Sendable {
    /// Extracts structured line items from receipt OCR text.
    func extractReceipt(_ input: ReceiptExtractionInput) async throws -> ReceiptExtraction

    /// Suggests recipes that use the given inventory.
    func suggestRecipes(_ request: RecipeRequest) async throws -> [Recipe]

    /// Lists the products visible in a photo of a shelf, fridge or cupboard.
    func scanShelf(_ input: ShelfScanInput) async throws -> ShelfScanResult

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

    public func scanShelf(_ input: ShelfScanInput) async throws -> ShelfScanResult {
        guard !input.image.isEmpty else { return ShelfScanResult(items: []) }
        // Image first, then the question: Claude reads images best that way.
        let content: JSONValue = [
            ContentBlock.image(input.image),
            ContentBlock.text(ShelfScanPrompt.userText(for: input)),
        ]
        return try await client.structuredOutput(
            ShelfScanResult.self,
            model: model(),
            system: ShelfScanPrompt.system,
            userContent: content,
            schema: ShelfScanSchema.schema
        )
    }

    public func verify() async throws {
        try await client.verify(model: model())
    }
}

/// Canned responses for previews, tests, and the offline demo.
public struct MockLLMService: LLMService {
    public var receipt: ReceiptExtraction
    public var recipes: [Recipe]
    public var shelf: ShelfScanResult
    public var delay: TimeInterval

    public init(
        receipt: ReceiptExtraction = SampleReceipt.extraction,
        recipes: [Recipe] = SampleRecipes.recipes,
        shelf: ShelfScanResult = SampleShelfScan.result,
        delay: TimeInterval = 0
    ) {
        self.receipt = receipt
        self.recipes = recipes
        self.shelf = shelf
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

    public func scanShelf(_ input: ShelfScanInput) async throws -> ShelfScanResult {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return shelf
    }

    public func verify() async throws {}
}
