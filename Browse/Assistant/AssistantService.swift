import Foundation

/// Builds provider requests and turns their SSE streams into text deltas.
/// Mirrors the protocol layer in the Sidecar extension so behavior matches
/// across both products.
enum AssistantService {

    struct Prepared: Sendable {
        var request: URLRequest
        var kind: AssistantProviderKind
    }

    enum ServiceError: LocalizedError {
        case badURL(String)
        case badStatus(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .badURL(let value): "Invalid base URL: \(value)"
            case .badStatus(let code, let body): "HTTP \(code): \(body)"
            case .emptyResponse: "The endpoint returned no body."
            }
        }
    }

    // MARK: Request

    static func prepare(
        provider: AssistantProvider,
        messages: [(role: String, content: String)],
        system: String
    ) throws -> Prepared {
        let base = normalizeBase(provider.baseURL, kind: provider.kind)
        guard let baseURL = URL(string: base) else { throw ServiceError.badURL(provider.baseURL) }

        var request: URLRequest
        var body: [String: Any]

        switch provider.kind {
        case .openai:
            var url = baseURL
            url.appendPathComponent("chat/completions")
            var chat: [[String: Any]] = [["role": "system", "content": system]]
            chat.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })
            body = [
                "model": provider.model,
                "messages": chat,
                "stream": true,
                "temperature": 0.7
            ]
            request = URLRequest(url: url)
            if !provider.apiKey.isEmpty {
                request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
            }

        case .anthropic:
            var url = baseURL
            url.appendPathComponent("messages")
            var anthropicMessages: [[String: Any]] = []
            for message in messages {
                let role = message.role == "assistant" ? "assistant" : "user"
                if let last = anthropicMessages.last,
                   let lastRole = last["role"] as? String,
                   lastRole == role,
                   var lastContent = last["content"] as? String {
                    lastContent += "\n\n" + message.content
                    anthropicMessages[anthropicMessages.count - 1]["content"] = lastContent
                } else {
                    anthropicMessages.append(["role": role, "content": message.content])
                }
            }
            body = [
                "model": provider.model,
                "max_tokens": 4096,
                "messages": anthropicMessages,
                "system": system,
                "stream": true,
                "temperature": 0.7
            ]
            request = URLRequest(url: url)
            request.setValue(provider.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        case .gemini:
            var url = baseURL
            url.appendPathComponent("models")
            url.appendPathComponent("\(provider.model):streamGenerateContent")
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "alt", value: "sse")]
            guard let finalURL = components?.url else { throw ServiceError.badURL(provider.baseURL) }
            var contents: [[String: Any]] = []
            for message in messages {
                contents.append([
                    "role": message.role == "assistant" ? "model" : "user",
                    "parts": [["text": message.content]]
                ])
            }
            body = [
                "contents": contents,
                "systemInstruction": ["parts": [["text": system]]],
                "generationConfig": ["temperature": 0.7]
            ]
            request = URLRequest(url: finalURL)
            request.setValue(provider.apiKey, forHTTPHeaderField: "x-goog-api-key")
        }

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 300
        return Prepared(request: request, kind: provider.kind)
    }

    static func normalizeBase(_ raw: String, kind: AssistantProviderKind) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        for suffix in ["/chat/completions", "/messages", "/models"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        return value.isEmpty ? kind.defaultBaseURL : value
    }

    // MARK: Stream

    static func stream(_ prepared: Prepared) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: prepared.request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ServiceError.emptyResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var text = ""
                        for try await line in bytes.lines {
                            text += line
                            if text.count > 600 { break }
                        }
                        throw ServiceError.badStatus(http.statusCode, text.trimmingCharacters(in: .whitespacesAndNewlines))
                    }

                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                let payload = dataLines.joined(separator: "\n")
                                dataLines.removeAll(keepingCapacity: true)
                                if payload == "[DONE]" { break }
                                if let delta = decode(kind: prepared.kind, payload: payload), !delta.isEmpty {
                                    continuation.yield(delta)
                                }
                            }
                            continue
                        }
                        if line.hasPrefix(":") { continue }
                        if line.hasPrefix("data:") {
                            var value = String(line.dropFirst(5))
                            if value.hasPrefix(" ") { value.removeFirst() }
                            dataLines.append(value)
                        }
                    }
                    if !dataLines.isEmpty,
                       let delta = decode(kind: prepared.kind, payload: dataLines.joined(separator: "\n")),
                       !delta.isEmpty {
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func decode(kind: AssistantProviderKind, payload: String) -> String? {
        guard
            let data = payload.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let text: String?
        switch kind {
        case .openai:
            let choices = object["choices"] as? [[String: Any]]
            let delta = choices?.first?["delta"] as? [String: Any]
            text = delta?["content"] as? String

        case .anthropic:
            if object["type"] as? String == "content_block_delta" {
                let delta = object["delta"] as? [String: Any]
                text = delta?["text"] as? String
            } else {
                text = nil
            }

        case .gemini:
            let candidates = object["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]]
            text = parts?.compactMap { $0["text"] as? String }.joined()
        }

        return text?.replacingOccurrences(of: "</think>", with: "")
            .replacingOccurrences(of: "<think>", with: "")
    }
}
