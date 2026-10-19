import Foundation

// MARK: - Provider model

enum AssistantProviderKind: String, CaseIterable, Codable, Sendable {
    case openai
    case anthropic
    case gemini

    var label: String {
        switch self {
        case .openai: "OpenAI-compatible"
        case .anthropic: "Anthropic"
        case .gemini: "Google Gemini"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openai: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: "gpt-4.1-mini"
        case .anthropic: "claude-sonnet-4-5"
        case .gemini: "gemini-2.5-flash"
        }
    }
}

struct AssistantProvider: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var label: String
    var kind: AssistantProviderKind
    var baseURL: String
    var apiKey: String
    var model: String

    init(
        id: UUID = UUID(),
        label: String,
        kind: AssistantProviderKind,
        baseURL: String,
        apiKey: String = "",
        model: String
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }
}

struct AssistantConfig: Codable, Sendable {
    var providers: [AssistantProvider]
    var activeProviderID: UUID
    var systemPrompt: String
    var temperature: Double
    var includePageByDefault: Bool

    static func makeDefault() -> AssistantConfig {
        let local = AssistantProvider(
            label: "Local · Nemotron 74B-A9B (MoE)",
            kind: .openai,
            baseURL: "http://192.168.1.150:8080/v1",
            model: "nemotron-bolt"
        )
        let vllm = AssistantProvider(
            label: "Local · hyper-qwen (vLLM)",
            kind: .openai,
            baseURL: "http://192.168.1.150:18020/v1",
            model: "qwen3.8-27b"
        )
        let openai = AssistantProvider(
            label: "OpenAI",
            kind: .openai,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4.1-mini"
        )
        let anthropic = AssistantProvider(
            label: "Anthropic",
            kind: .anthropic,
            baseURL: "https://api.anthropic.com/v1",
            model: "claude-sonnet-4-5"
        )
        let gemini = AssistantProvider(
            label: "Google Gemini",
            kind: .gemini,
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            model: "gemini-2.5-flash"
        )
        return AssistantConfig(
            providers: [local, vllm, openai, anthropic, gemini],
            activeProviderID: local.id,
            systemPrompt:
                "You are Sidecar, a concise assistant built into the browser. " +
                "Ground answers in the page when context is provided and say plainly when the page " +
                "does not contain the answer. Never invent URLs or quotes.",
            temperature: 0.7,
            includePageByDefault: true
        )
    }
}

// MARK: - Chat message

struct AssistantMessage: Identifiable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    let id: UUID
    var role: Role
    var content: String
    var error: String?

    init(id: UUID = UUID(), role: Role, content: String, error: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.error = error
    }
}

// MARK: - Persistence

enum AssistantConfigStore {
    static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Blur-Browser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("assistant.json")
    }

    static func load() -> AssistantConfig {
        guard
            let data = try? Data(contentsOf: fileURL),
            let config = try? JSONDecoder().decode(AssistantConfig.self, from: data)
        else {
            return .makeDefault()
        }
        return config
    }

    static func save(_ config: AssistantConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
