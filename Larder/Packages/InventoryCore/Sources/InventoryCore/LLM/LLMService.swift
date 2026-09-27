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

    /// Lists what's being thrown out or used up in photos, matched to inventory.
    func scanOut(_ input: ScanOutInput) async throws -> ScanOutResult

    /// Reads a recipe from photos of it, matching ingredients to inventory.
    func readRecipe(_ input: RecipeScanInput) async throws -> Recipe

    /// Turns a typed or dictated list into items.
    func parseQuickAdd(_ text: String) async throws -> QuickAddResult

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
        guard !input.images.isEmpty else { return ShelfScanResult(items: []) }
        // Images first, then the question: Claude reads images best that way.
        let content = JSONValue.array(input.images.map { ContentBlock.image($0) } + [ContentBlock.text(ShelfScanPrompt.userText(for: input))])
        return try await client.structuredOutput(
            ShelfScanResult.self,
            model: model(),
            system: ShelfScanPrompt.system,
            userContent: content,
            schema: ShelfScanSchema.schema
        )
    }

    public func scanOut(_ input: ScanOutInput) async throws -> ScanOutResult {
        guard !input.images.isEmpty else { return ScanOutResult(items: []) }
        let content = JSONValue.array(input.images.map { ContentBlock.image($0) } + [ContentBlock.text(ScanOutPrompt.userText(for: input))])
        return try await client.structuredOutput(
            ScanOutResult.self,
            model: model(),
            system: ScanOutPrompt.system,
            userContent: content,
            schema: ScanOutSchema.schema
        )
    }

    public func readRecipe(_ input: RecipeScanInput) async throws -> Recipe {
        let content = JSONValue.array(input.images.map { ContentBlock.image($0) } + [ContentBlock.text(RecipeScanPrompt.userText(for: input))])
        return try await client.structuredOutput(
            Recipe.self,
            model: model(),
            system: RecipeScanPrompt.system,
            userContent: content,
            schema: RecipeScanPrompt.schema
        )
    }

    public func parseQuickAdd(_ text: String) async throws -> QuickAddResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return QuickAddResult(items: []) }
        return try await client.structuredOutput(
            QuickAddResult.self,
            model: model(),
            system: QuickAddPrompt.system,
            user: QuickAddPrompt.userText(for: text),
            schema: QuickAddSchema.schema
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
    public var scanOut: ScanOutResult
    public var delay: TimeInterval

    public init(
        receipt: ReceiptExtraction = SampleReceipt.extraction,
        recipes: [Recipe] = SampleRecipes.recipes,
        shelf: ShelfScanResult = SampleShelfScan.result,
        scanOut: ScanOutResult = SampleScanOut.result,
        delay: TimeInterval = 0
    ) {
        self.receipt = receipt
        self.recipes = recipes
        self.shelf = shelf
        self.scanOut = scanOut
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

    public func scanOut(_ input: ScanOutInput) async throws -> ScanOutResult {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return scanOut
    }

    public func readRecipe(_ input: RecipeScanInput) async throws -> Recipe {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return SampleScanOut.recipe
    }

    /// Parses on the phone, like the no-key fallback.
    public func parseQuickAdd(_ text: String) async throws -> QuickAddResult {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return QuickAddResult(items: QuickAddParser.parse(text))
    }

    public func verify() async throws {}
}
