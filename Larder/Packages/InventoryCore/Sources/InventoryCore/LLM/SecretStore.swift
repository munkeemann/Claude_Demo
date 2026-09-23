import Foundation

/// Storage for secrets such as the Anthropic API key. The app backs this with
/// the Keychain; nothing secret ever goes to UserDefaults or source code.
public protocol SecretStore: Sendable {
    func secret(for key: String) throws -> String?
    func setSecret(_ value: String, for key: String) throws
    func removeSecret(for key: String) throws
}

public enum SecretKey {
    public static let anthropicAPIKey = "anthropic.apiKey"
}

/// In-memory store for tests and previews.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public func secret(for key: String) throws -> String? {
        lock.withLock { values[key] }
    }

    public func setSecret(_ value: String, for key: String) throws {
        lock.withLock { values[key] = value }
    }

    public func removeSecret(for key: String) throws {
        lock.withLock { _ = values.removeValue(forKey: key) }
    }
}
