import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Claude models offered in Settings. Opus 5 is the default.
public enum ClaudeModel: String, CaseIterable, Codable, Sendable, Identifiable {
    case opus5 = "claude-opus-5"
    case sonnet5 = "claude-sonnet-5"
    case haiku45 = "claude-haiku-4-5"

    public static let `default`: ClaudeModel = .opus5

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .opus5: "Claude Opus 5"
        case .sonnet5: "Claude Sonnet 5"
        case .haiku45: "Claude Haiku 4.5"
        }
    }

    public var summary: String {
        switch self {
        case .opus5: "Most capable. Best at cryptic receipt abbreviations."
        case .sonnet5: "Faster and about 2.5× cheaper than Opus."
        case .haiku45: "Fastest and about 5× cheaper than Opus."
        }
    }

    /// Server-side refusal fallback (`fallbacks: "default"`) is enabled for
    /// Opus 5, which runs the safety classifiers that can decline requests.
    public var usesServerSideFallback: Bool { self == .opus5 }
}

public enum AnthropicError: Error, Equatable, Sendable {
    case missingAPIKey
    case invalidAPIKey
    case permissionDenied(String)
    case rateLimited(retryAfter: TimeInterval?)
    case overloaded
    case badRequest(String)
    case server(status: Int, message: String)
    /// Claude declined the request (`stop_reason: "refusal"`).
    case refused(category: String?)
    /// Output hit `max_tokens` before finishing.
    case truncated
    case emptyResponse
    case invalidJSON(String)
}

extension AnthropicError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your Anthropic API key in Settings to use this feature."
        case .invalidAPIKey: "The Anthropic API key was rejected. Check it in Settings."
        case .permissionDenied(let message): "Permission denied: \(message)"
        case .rateLimited: "Claude is rate limited right now. Try again in a minute."
        case .overloaded: "Claude is temporarily overloaded. Try again shortly."
        case .badRequest(let message): "The request was rejected: \(message)"
        case .server(let status, let message): "Claude returned an error (\(status)): \(message)"
        case .refused: "Claude declined this request."
        case .truncated: "Claude's response was cut off. Try a shorter input."
        case .emptyResponse: "Claude returned an empty response."
        case .invalidJSON(let detail): "Claude's response couldn't be read: \(detail)"
        }
    }
}

/// Minimal client for the Anthropic Messages API (`POST /v1/messages`).
/// There is no official Swift SDK, so this speaks raw HTTP.
public struct AnthropicClient: Sendable {
    public static let apiVersion = "2023-06-01"
    public static let fallbackBeta = "server-side-fallback-2026-07-01"

    private let http: any HTTPClient
    private let baseURL: URL
    private let apiKey: @Sendable () throws -> String?
    private let maxRetries: Int
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    /// - Parameter apiKey: Read on every request, so key changes in Settings
    ///   take effect immediately and the key is never cached here.
    public init(
        http: any HTTPClient = URLSessionHTTPClient(),
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        maxRetries: Int = 2,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        },
        apiKey: @escaping @Sendable () throws -> String?
    ) {
        self.http = http
        self.baseURL = baseURL
        self.maxRetries = maxRetries
        self.sleep = sleep
        self.apiKey = apiKey
    }

    // MARK: - Structured output

    /// Sends one user message constrained to `schema` and decodes the reply.
    public func structuredOutput<Output: Decodable>(
        _ type: Output.Type,
        model: ClaudeModel,
        system: String,
        user: String,
        schema: JSONValue,
        maxTokens: Int = 16_000
    ) async throws -> Output {
        let response = try await createMessage(
            model: model,
            system: system,
            user: user,
            outputSchema: schema,
            maxTokens: maxTokens
        )
        guard let text = response.content.last(where: { $0.type == "text" })?.text, !text.isEmpty else {
            throw AnthropicError.emptyResponse
        }
        do {
            return try JSONDecoder().decode(Output.self, from: Data(text.utf8))
        } catch {
            throw AnthropicError.invalidJSON(String(describing: error))
        }
    }

    /// Sends a single-turn request and validates the stop reason.
    public func createMessage(
        model: ClaudeModel,
        system: String,
        user: String,
        outputSchema: JSONValue? = nil,
        maxTokens: Int = 16_000
    ) async throws -> MessagesResponse {
        var body: [String: JSONValue] = [
            "model": .string(model.rawValue),
            "max_tokens": .integer(maxTokens),
            "system": .string(system),
            "messages": [["role": "user", "content": .string(user)]],
        ]
        if let outputSchema {
            body["output_config"] = ["format": ["type": "json_schema", "schema": outputSchema]]
        }
        var betas: [String] = []
        if model.usesServerSideFallback {
            body["fallbacks"] = "default"
            betas.append(Self.fallbackBeta)
        }
        let request = try makeRequest(path: "/v1/messages", method: "POST", body: .object(body), betas: betas)
        let data = try await send(request)

        let response: MessagesResponse
        do {
            response = try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw AnthropicError.invalidJSON(String(describing: error))
        }
        switch response.stopReason {
        case "refusal":
            throw AnthropicError.refused(category: response.stopDetails?.category)
        case "max_tokens":
            throw AnthropicError.truncated
        default:
            return response
        }
    }

    /// Checks the key and model access without generating tokens
    /// (`GET /v1/models/{id}`).
    public func verify(model: ClaudeModel) async throws {
        let request = try makeRequest(path: "/v1/models/\(model.rawValue)", method: "GET", body: nil, betas: [])
        _ = try await send(request)
    }

    // MARK: - Transport

    func makeRequest(path: String, method: String, body: JSONValue?, betas: [String]) throws -> URLRequest {
        guard let key = try apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw AnthropicError.missingAPIKey
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 300
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if !betas.isEmpty {
            request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try body.encoded()
        }
        return request
    }

    /// Sends with retries on 408/409/429/5xx and connection errors, honoring
    /// `retry-after` when present.
    func send(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await http.send(request)
            } catch let error as URLError where attempt < maxRetries && Self.isTransient(error) {
                attempt += 1
                try await sleep(Self.backoff(attempt: attempt, retryAfter: nil))
                continue
            }

            let status = response.statusCode
            if (200..<300).contains(status) { return data }

            let retryAfter = response.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            if Self.isRetryable(status), attempt < maxRetries {
                attempt += 1
                try await sleep(Self.backoff(attempt: attempt, retryAfter: retryAfter))
                continue
            }
            throw Self.error(status: status, data: data, retryAfter: retryAfter)
        }
    }

    static func isRetryable(_ status: Int) -> Bool {
        status == 408 || status == 409 || status == 429 || status >= 500
    }

    static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed: true
        default: false
        }
    }

    static func backoff(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter { return min(retryAfter, 60) }
        return min(pow(2, Double(attempt - 1)), 8)
    }

    static func error(status: Int, data: Data, retryAfter: TimeInterval?) -> AnthropicError {
        let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
            ?? String(data: data, encoding: .utf8)
            ?? ""
        switch status {
        case 400, 404, 413, 422: return .badRequest(message)
        case 401: return .invalidAPIKey
        case 403: return .permissionDenied(message)
        case 429: return .rateLimited(retryAfter: retryAfter)
        case 529: return .overloaded
        default: return .server(status: status, message: message)
        }
    }
}

// MARK: - Wire types

public struct MessagesResponse: Decodable, Sendable {
    public struct ContentBlock: Decodable, Sendable {
        public let type: String
        public let text: String?
    }

    public struct StopDetails: Decodable, Sendable {
        public let type: String?
        public let category: String?
        public let explanation: String?
    }

    public struct Usage: Decodable, Sendable {
        public let inputTokens: Int?
        public let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    public let id: String?
    public let model: String?
    public let content: [ContentBlock]
    public let stopReason: String?
    public let stopDetails: StopDetails?
    public let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case id, model, content, usage
        case stopReason = "stop_reason"
        case stopDetails = "stop_details"
    }
}

struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let type: String?
        let message: String
    }

    let error: Detail
}
