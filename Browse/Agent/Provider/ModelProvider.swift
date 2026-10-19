import Foundation

// MARK: - JSON value

/// A JSON value the agent can pass between the model and its tools without
/// committing to a concrete Codable type for every tool input.
enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// Compact JSON for display in approval cards and logs.
    var compactDescription: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Provider-neutral transcript

/// One block of a turn. `opaque` carries provider-specific blocks (e.g. Claude
/// `thinking` blocks) that must be echoed back unchanged on the next request.
enum AgentContentBlock: Sendable, Equatable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String, content: String, isError: Bool)
    case opaque(JSONValue)
}

struct AgentMessage: Sendable, Equatable {
    enum Role: String, Sendable { case user, assistant }
    let role: Role
    var blocks: [AgentContentBlock]
}

/// Tool definition handed to the model: name, description, JSON Schema.
struct ModelToolDefinition: Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue
}

struct ModelResponse: Sendable {
    enum StopReason: Sendable, Equatable {
        case endTurn, toolUse, maxTokens, refusal, other(String)
    }
    let blocks: [AgentContentBlock]
    let stopReason: StopReason
}

enum ModelProviderError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key set. Add one in Settings → AI."
        case .http(let status, let message):
            return "The model request failed (\(status)): \(message)"
        case .decoding(let detail):
            return "Couldn't read the model response: \(detail)"
        }
    }
}

/// A chat model that can call tools. Implementations own the wire format; the
/// agent loop only sees `AgentMessage`s. Add new backends by conforming here.
protocol ModelProvider: Sendable {
    var displayName: String { get }
    func respond(
        system: String,
        messages: [AgentMessage],
        tools: [ModelToolDefinition]
    ) async throws -> ModelResponse
}
