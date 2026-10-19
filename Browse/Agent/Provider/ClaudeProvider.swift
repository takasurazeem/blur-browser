import Foundation

/// Claude via the Messages API (`POST /v1/messages`) over plain URLSession —
/// there's no official Swift SDK and the project takes no third-party deps.
///
/// The API key is read from the Keychain on every request, so changing it in
/// Settings → AI takes effect immediately and the key never sits in memory
/// longer than one call.
struct ClaudeProvider: ModelProvider {
    static let defaultModel = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Models that accept `fallbacks: "default"` (server-side refusal fallback).
    private static let fallbackModels: Set<String> = [
        "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]

    let model: String
    let effort: String
    var displayName: String { "Claude (\(model))" }

    init(model: String = Self.defaultModel, effort: String = "medium") {
        self.model = model
        self.effort = effort
    }

    func respond(
        system: String,
        messages: [AgentMessage],
        tools: [ModelToolDefinition]
    ) async throws -> ModelResponse {
        guard let apiKey = KeychainStore.read(account: KeychainStore.anthropicAccount),
              !apiKey.isEmpty else {
            throw ModelProviderError.missingAPIKey
        }

        var body: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .number(16000),
            "system": .string(system),
            "messages": .array(messages.map(Self.encode)),
            "tools": .array(tools.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "input_schema": tool.inputSchema,
                ])
            }),
            "output_config": .object(["effort": .string(effort)]),
        ]
        let useFallbacks = Self.fallbackModels.contains(model)
        if useFallbacks {
            body["fallbacks"] = .string("default")
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if useFallbacks {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json: JSONValue
        do {
            json = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw ModelProviderError.http(status: status, message: String(decoding: data.prefix(300), as: UTF8.self))
        }
        guard (200..<300).contains(status) else {
            let message = json["error"]?["message"]?.stringValue ?? "Unknown error"
            throw ModelProviderError.http(status: status, message: message)
        }
        return try Self.decode(json)
    }

    // MARK: - Wire format

    private static func encode(_ message: AgentMessage) -> JSONValue {
        let content: [JSONValue] = message.blocks.map { block in
            switch block {
            case .text(let text):
                return .object(["type": .string("text"), "text": .string(text)])
            case .toolUse(let id, let name, let input):
                return .object([
                    "type": .string("tool_use"), "id": .string(id),
                    "name": .string(name), "input": input,
                ])
            case .toolResult(let id, let content, let isError):
                return .object([
                    "type": .string("tool_result"), "tool_use_id": .string(id),
                    "content": .string(content), "is_error": .bool(isError),
                ])
            case .opaque(let raw):
                return raw
            }
        }
        return .object(["role": .string(message.role.rawValue), "content": .array(content)])
    }

    private static func decode(_ json: JSONValue) throws -> ModelResponse {
        guard case .array(let content)? = json["content"] else {
            throw ModelProviderError.decoding("missing content")
        }
        // Every block is kept, in order — thinking blocks must be echoed back
        // unchanged on the next turn, so anything we don't render is opaque.
        let blocks: [AgentContentBlock] = content.map { block in
            switch block["type"]?.stringValue {
            case "text":
                return .text(block["text"]?.stringValue ?? "")
            case "tool_use":
                return .toolUse(
                    id: block["id"]?.stringValue ?? UUID().uuidString,
                    name: block["name"]?.stringValue ?? "",
                    input: block["input"] ?? .object([:])
                )
            default:
                return .opaque(block)
            }
        }
        let stop: ModelResponse.StopReason
        switch json["stop_reason"]?.stringValue {
        case "end_turn", "stop_sequence": stop = .endTurn
        case "tool_use": stop = .toolUse
        case "max_tokens": stop = .maxTokens
        case "refusal": stop = .refusal
        case let other: stop = .other(other ?? "unknown")
        }
        return ModelResponse(blocks: blocks, stopReason: stop)
    }
}
