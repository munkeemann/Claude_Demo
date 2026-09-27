import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import InventoryCore

/// Plays back a scripted sequence of responses and records requests.
final class ScriptedHTTPClient: HTTPClient, @unchecked Sendable {
    enum Step {
        case respond(status: Int, body: String, headers: [String: String] = [:])
        case fail(URLError.Code)
    }

    private let lock = NSLock()
    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let step: Step = lock.withLock {
            requests.append(request)
            return steps.isEmpty ? .respond(status: 500, body: "no more steps") : steps.removeFirst()
        }
        switch step {
        case .fail(let code):
            throw URLError(code)
        case .respond(let status, let body, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (Data(body.utf8), response)
        }
    }

    var requestCount: Int { lock.withLock { requests.count } }

    func body(at index: Int) throws -> JSONValue {
        let data = try #require(lock.withLock { requests[index].httpBody })
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var delays: [TimeInterval] = []
    func record(_ delay: TimeInterval) { lock.withLock { delays.append(delay) } }
}

enum MessagesFixtures {
    static func success(text: String, stopReason: String = "end_turn") -> String {
        let escaped = String(data: try! JSONEncoder().encode(text), encoding: .utf8)!
        return """
        {"id":"msg_01","type":"message","role":"assistant","model":"claude-opus-5",
         "content":[{"type":"thinking","thinking":"","signature":"sig"},{"type":"text","text":\(escaped)}],
         "stop_reason":"\(stopReason)","stop_details":null,"usage":{"input_tokens":1200,"output_tokens":800}}
        """
    }

    static let refusal = """
    {"id":"msg_02","type":"message","role":"assistant","model":"claude-opus-5","content":[],
     "stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber","explanation":"declined"},
     "usage":{"input_tokens":10,"output_tokens":0}}
    """

    static let overloaded = """
    {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}
    """

    static let invalidRequest = """
    {"type":"error","error":{"type":"invalid_request_error","message":"max_tokens: must be positive"}}
    """
}

struct AnthropicClientTests {
    func makeClient(_ http: ScriptedHTTPClient, key: String? = "sk-ant-test", sleeps: SleepRecorder = SleepRecorder()) -> AnthropicClient {
        AnthropicClient(http: http, sleep: { sleeps.record($0) }, apiKey: { key })
    }

    @Test func sendsHeadersAndStructuredOutputBody() async throws {
        let http = ScriptedHTTPClient([.respond(status: 200, body: MessagesFixtures.success(text: SampleReceipt.extractionJSON))])
        let service = AnthropicLLMService(client: makeClient(http), model: { .opus5 })

        let extraction = try await service.extractReceipt(ReceiptExtractionInput(ocrText: SampleReceipt.ocrText))
        #expect(extraction == SampleReceipt.extraction)

        let request = try #require(http.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")

        let body = try http.body(at: 0)
        #expect(body["model"] == "claude-opus-5")
        #expect(body["max_tokens"] == 16_000)
        #expect(body["fallbacks"] == "default")
        #expect(body["system"]?.stringValue == ReceiptPrompt.system)
        #expect(body["output_config"]?["format"]?["type"] == "json_schema")
        #expect(body["output_config"]?["format"]?["schema"] == ReceiptExtractionSchema.schema)
        #expect(body["thinking"] == nil, "Opus 5 runs adaptive thinking by default")
        let message = try #require(body["messages"]?.arrayValue?.first)
        #expect(message["role"] == "user")
        #expect(message["content"]?.stringValue?.contains("GV WHL MLK 1G") == true)
    }

    @Test func otherModelsDoNotSendFallbacks() async throws {
        let http = ScriptedHTTPClient([.respond(status: 200, body: MessagesFixtures.success(text: SampleReceipt.extractionJSON))])
        let service = AnthropicLLMService(client: makeClient(http), model: { .haiku45 })
        _ = try await service.extractReceipt(ReceiptExtractionInput(ocrText: "BANANAS 1.33"))
        let body = try http.body(at: 0)
        #expect(body["model"] == "claude-haiku-4-5")
        #expect(body["fallbacks"] == nil)
        #expect(http.requests.first?.value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    @Test func requestBodyIsDeterministic() throws {
        let client = makeClient(ScriptedHTTPClient([]))
        let body: JSONValue = ["b": 1, "a": ["z": true, "y": "x"]]
        let first = try client.makeRequest(path: "/v1/messages", method: "POST", body: body, betas: []).httpBody
        let second = try client.makeRequest(path: "/v1/messages", method: "POST", body: body, betas: []).httpBody
        #expect(first == second)
        #expect(String(data: first!, encoding: .utf8) == #"{"a":{"y":"x","z":true},"b":1}"#)
    }

    @Test func missingKeyFailsBeforeAnyRequest() async {
        let http = ScriptedHTTPClient([])
        let service = AnthropicLLMService(client: makeClient(http, key: "  "), model: { .opus5 })
        await #expect(throws: AnthropicError.missingAPIKey) {
            try await service.extractReceipt(ReceiptExtractionInput(ocrText: "MILK 3.42"))
        }
        #expect(http.requestCount == 0)
    }

    @Test func emptyOCRTextSkipsTheCall() async throws {
        let http = ScriptedHTTPClient([])
        let service = AnthropicLLMService(client: makeClient(http), model: { .opus5 })
        let extraction = try await service.extractReceipt(ReceiptExtractionInput(ocrText: " \n "))
        #expect(extraction.items.isEmpty)
        #expect(http.requestCount == 0)
    }

    @Test func refusalIsSurfaced() async {
        let http = ScriptedHTTPClient([.respond(status: 200, body: MessagesFixtures.refusal)])
        await #expect(throws: AnthropicError.refused(category: "cyber")) {
            try await makeClient(http).createMessage(model: .opus5, system: "s", user: "u")
        }
    }

    @Test func truncationIsSurfaced() async {
        let http = ScriptedHTTPClient([.respond(status: 200, body: MessagesFixtures.success(text: "{\"items\": [", stopReason: "max_tokens"))])
        await #expect(throws: AnthropicError.truncated) {
            try await makeClient(http).structuredOutput(ReceiptExtraction.self, model: .opus5, system: "s", user: "u", schema: ReceiptExtractionSchema.schema)
        }
    }

    @Test func malformedJSONIsReported() async {
        let http = ScriptedHTTPClient([.respond(status: 200, body: MessagesFixtures.success(text: "not json"))])
        await #expect(throws: AnthropicError.self) {
            try await makeClient(http).structuredOutput(ReceiptExtraction.self, model: .opus5, system: "s", user: "u", schema: ReceiptExtractionSchema.schema)
        }
    }

    @Test func retriesOverloadedThenSucceeds() async throws {
        let sleeps = SleepRecorder()
        let http = ScriptedHTTPClient([
            .respond(status: 529, body: MessagesFixtures.overloaded),
            .fail(.networkConnectionLost),
            .respond(status: 200, body: MessagesFixtures.success(text: "{}")),
        ])
        let response = try await makeClient(http, sleeps: sleeps).createMessage(model: .opus5, system: "s", user: "u")
        #expect(response.content.last?.text == "{}")
        #expect(http.requestCount == 3)
        #expect(sleeps.delays == [1, 2])
    }

    @Test func honorsRetryAfterThenGivesUp() async {
        let sleeps = SleepRecorder()
        let limited = ScriptedHTTPClient.Step.respond(status: 429, body: "{}", headers: ["retry-after": "7"])
        let http = ScriptedHTTPClient([limited, limited, limited])
        await #expect(throws: AnthropicError.rateLimited(retryAfter: 7)) {
            try await makeClient(http, sleeps: sleeps).createMessage(model: .opus5, system: "s", user: "u")
        }
        #expect(http.requestCount == 3)
        #expect(sleeps.delays == [7, 7])
    }

    @Test func clientErrorsAreNotRetried() async {
        let http = ScriptedHTTPClient([.respond(status: 400, body: MessagesFixtures.invalidRequest)])
        await #expect(throws: AnthropicError.badRequest("max_tokens: must be positive")) {
            try await makeClient(http).createMessage(model: .opus5, system: "s", user: "u")
        }
        #expect(http.requestCount == 1)
    }

    @Test func invalidKeyIsReported() async {
        let body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        let http = ScriptedHTTPClient([.respond(status: 401, body: body)])
        await #expect(throws: AnthropicError.invalidAPIKey) {
            try await makeClient(http).verify(model: .opus5)
        }
    }

    @Test func verifyUsesModelsEndpoint() async throws {
        let http = ScriptedHTTPClient([.respond(status: 200, body: #"{"id":"claude-sonnet-5","type":"model"}"#)])
        try await makeClient(http).verify(model: .sonnet5)
        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/models/claude-sonnet-5")
        #expect(request.httpBody == nil)
    }
}
