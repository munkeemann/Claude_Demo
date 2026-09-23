import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import InventoryCore

/// Returns canned responses keyed by URL host, and records every request.
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    struct Response {
        var status: Int
        var body: String
    }

    private let lock = NSLock()
    private var responses: [String: Response]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [String: Response]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = lock.withLock {
            requests.append(request)
            return request.url?.host.flatMap { responses[$0] } ?? Response(status: 404, body: "{}")
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(response.body.utf8), http)
    }

    var requestedHosts: [String] {
        lock.withLock { requests.compactMap { $0.url?.host } }
    }
}
