import Foundation

/// A JSON document, used to build request bodies and JSON schemas without
/// hand-writing Codable types for every shape.
public enum JSONValue: Sendable, Hashable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Serializes with sorted keys so identical inputs produce identical bytes
    /// (keeps prompt-cache prefixes stable).
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByFloatLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .integer(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

/// Builders for JSON schemas that satisfy the structured-output rules:
/// every object lists all properties as required and sets
/// `additionalProperties: false`; optional values are expressed as nullable.
public enum JSONSchema {
    public static func object(_ properties: [(String, JSONValue)], description: String? = nil) -> JSONValue {
        var schema: [String: JSONValue] = [
            "type": "object",
            "properties": .object(Dictionary(properties, uniquingKeysWith: { _, last in last })),
            "required": .array(properties.map { .string($0.0) }),
            "additionalProperties": false,
        ]
        if let description { schema["description"] = .string(description) }
        return .object(schema)
    }

    public static func string(_ description: String? = nil) -> JSONValue {
        typed("string", description)
    }

    public static func number(_ description: String? = nil) -> JSONValue {
        typed("number", description)
    }

    public static func integer(_ description: String? = nil) -> JSONValue {
        typed("integer", description)
    }

    public static func boolean(_ description: String? = nil) -> JSONValue {
        typed("boolean", description)
    }

    public static func enumeration(_ values: [String], description: String? = nil) -> JSONValue {
        var schema: [String: JSONValue] = ["type": "string", "enum": .array(values.map { .string($0) })]
        if let description { schema["description"] = .string(description) }
        return .object(schema)
    }

    public static func array(of items: JSONValue, description: String? = nil) -> JSONValue {
        var schema: [String: JSONValue] = ["type": "array", "items": items]
        if let description { schema["description"] = .string(description) }
        return .object(schema)
    }

    /// `schema` or null.
    public static func nullable(_ schema: JSONValue) -> JSONValue {
        ["anyOf": [schema, ["type": "null"]]]
    }

    private static func typed(_ type: String, _ description: String?) -> JSONValue {
        var schema: [String: JSONValue] = ["type": .string(type)]
        if let description { schema["description"] = .string(description) }
        return .object(schema)
    }
}
