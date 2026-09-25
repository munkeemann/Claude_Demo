import Foundation

/// Every kind of record a household shares. Listed so that referenced
/// kinds come before the kinds that point at them.
public enum SyncKind: String, Codable, CaseIterable, Sendable {
    case location
    case product
    case alias
    case receipt
    case item
    case purchase
    case usage
    case shoppingItem
    case savedRecipe

    /// Apply incoming records in this order so references resolve.
    public var applyOrder: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// A pointer from one record to another ("this item's product").
public struct SyncRef: Codable, Hashable, Sendable {
    public var kind: SyncKind
    public var id: UUID

    public init(_ kind: SyncKind, _ id: UUID) {
        self.kind = kind
        self.id = id
    }
}

/// One shared record: a model object's fields as JSON plus its references.
///
/// Everything a household shares travels as one CloudKit record type whose
/// payload is this envelope, so adding a field never needs a CloudKit
/// schema change, and a phone on an older version keeps fields it doesn't
/// know about instead of erasing them.
public struct SyncEnvelope: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var v: Int
    public var kind: SyncKind
    public var id: UUID
    public var fields: [String: JSONValue]
    public var refs: [String: SyncRef]

    public init(kind: SyncKind, id: UUID, fields: [String: JSONValue] = [:], refs: [String: SyncRef] = [:]) {
        v = Self.currentVersion
        self.kind = kind
        self.id = id
        self.fields = fields
        self.refs = refs
    }

    public var recordName: String { SyncRecordName.make(kind, id) }

    /// Canonical bytes: identical envelopes always encode identically, which
    /// is how unchanged records are recognized.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> SyncEnvelope {
        try JSONDecoder().decode(SyncEnvelope.self, from: data)
    }

    /// Merges in what this version of the app can't express from the last
    /// version everyone agreed on:
    /// - fields it doesn't know (written by a newer version), and
    /// - references whose target isn't here yet (it may still be on its
    ///   way), so a half-synced phone doesn't erase them.
    /// A reference whose target is here but was cleared is a real edit and
    /// stays cleared.
    public func preserving(from previous: SyncEnvelope?, referenceExists: (SyncRef) -> Bool) -> SyncEnvelope {
        guard let previous, previous.kind == kind, previous.id == id else { return self }
        var merged = self
        for (key, value) in previous.fields where merged.fields[key] == nil {
            merged.fields[key] = value
        }
        for (key, ref) in previous.refs where merged.refs[key] == nil && !referenceExists(ref) {
            merged.refs[key] = ref
        }
        return merged
    }
}

/// CloudKit record names: "<kind>.<UUID>".
public enum SyncRecordName {
    public static func make(_ kind: SyncKind, _ id: UUID) -> String {
        "\(kind.rawValue).\(id.uuidString)"
    }

    public static func parse(_ name: String) -> (kind: SyncKind, id: UUID)? {
        guard let dot = name.firstIndex(of: ".") else { return nil }
        guard let kind = SyncKind(rawValue: String(name[..<dot])),
              let id = UUID(uuidString: String(name[name.index(after: dot)...]))
        else { return nil }
        return (kind, id)
    }
}

// MARK: - Field coding

/// Writes model properties into envelope fields. Dates are stored as
/// seconds since the reference date, which round-trips exactly.
public struct SyncFieldWriter {
    public private(set) var fields: [String: JSONValue] = [:]

    public init() {}

    public mutating func set(_ key: String, _ value: String?) {
        fields[key] = value.map(JSONValue.string) ?? .null
    }

    public mutating func set(_ key: String, _ value: Double) {
        fields[key] = .number(value)
    }

    public mutating func set(_ key: String, _ value: Int?) {
        fields[key] = value.map(JSONValue.integer) ?? .null
    }

    public mutating func set(_ key: String, _ value: Bool) {
        fields[key] = .bool(value)
    }

    public mutating func set(_ key: String, _ value: Date?) {
        fields[key] = value.map { .number($0.timeIntervalSinceReferenceDate) } ?? .null
    }

    public mutating func set(_ key: String, _ value: Data?) {
        fields[key] = value.map { .string($0.base64EncodedString()) } ?? .null
    }
}

/// Reads envelope fields back. A missing key means the sender didn't know
/// the field, so callers leave the local value alone; `has` tells the
/// difference between missing and null.
public struct SyncFieldReader {
    public let fields: [String: JSONValue]

    public init(_ fields: [String: JSONValue]) {
        self.fields = fields
    }

    public func has(_ key: String) -> Bool { fields[key] != nil }

    public func string(_ key: String) -> String? {
        fields[key]?.stringValue
    }

    public func double(_ key: String) -> Double? {
        switch fields[key] {
        case .number(let value): value
        case .integer(let value): Double(value)
        default: nil
        }
    }

    public func int(_ key: String) -> Int? {
        switch fields[key] {
        case .integer(let value): value
        case .number(let value) where value == value.rounded(): Int(value)
        default: nil
        }
    }

    public func bool(_ key: String) -> Bool? {
        if case .bool(let value) = fields[key] { return value }
        return nil
    }

    public func date(_ key: String) -> Date? {
        double(key).map(Date.init(timeIntervalSinceReferenceDate:))
    }

    public func data(_ key: String) -> Data? {
        string(key).flatMap { Data(base64Encoded: $0) }
    }
}

// MARK: - Change detection

/// Compares what's on this phone with what was last agreed with iCloud.
public enum SyncDiff {
    public struct Result: Equatable, Sendable {
        /// Records to upload: new, or changed since last agreed.
        public var saves: [String]
        /// Records to delete: agreed before, gone from this phone now.
        public var deletes: [String]
    }

    /// - Parameters:
    ///   - current: Every record on this phone, by record name.
    ///   - agreed: The last payload iCloud confirmed for each known record
    ///     (nil when a record was queued but never confirmed).
    public static func compute(current: [String: Data], agreed: [String: Data?]) -> Result {
        let saves = current.compactMap { name, payload -> String? in
            guard let known = agreed[name], let known else { return name }
            return known == payload ? nil : name
        }
        let deletes = agreed.keys.filter { current[$0] == nil }
        return Result(saves: saves.sorted(), deletes: deletes.sorted())
    }
}

/// Two phones changed the same record: the later change wins.
public enum SyncConflict {
    public enum Resolution: Equatable, Sendable {
        case keepLocal
        case takeServer
    }

    public static func resolve(localChangedAt: Date?, serverModifiedAt: Date?) -> Resolution {
        guard let serverModifiedAt else { return .keepLocal }
        guard let localChangedAt else { return .takeServer }
        return localChangedAt > serverModifiedAt ? .keepLocal : .takeServer
    }
}
