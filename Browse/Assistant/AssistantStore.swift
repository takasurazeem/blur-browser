import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class AssistantStore {
    let tabManager: TabManager

    var config: AssistantConfig
    var messages: [AssistantMessage] = []
    var isStreaming = false
    var includePage: Bool

    private var streamTask: Task<Void, Never>?

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        let loaded = AssistantConfigStore.load()
        self.config = loaded
        self.includePage = loaded.includePageByDefault
    }

    var activeProvider: AssistantProvider? {
        config.providers.first { $0.id == config.activeProviderID } ?? config.providers.first
    }

    func selectProvider(_ id: UUID) {
        config.activeProviderID = id
        AssistantConfigStore.save(config)
    }

    func apply(_ newConfig: AssistantConfig) {
        config = newConfig
        if !config.providers.contains(where: { $0.id == config.activeProviderID }) {
            config.activeProviderID = config.providers.first?.id ?? UUID()
        }
        AssistantConfigStore.save(config)
    }

    func clear() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        messages.removeAll()
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, let provider = activeProvider else { return }

        messages.append(AssistantMessage(role: .user, content: text))
        let assistantID = UUID()
        messages.append(AssistantMessage(id: assistantID, role: .assistant, content: ""))
        isStreaming = true

        let history = messages
            .filter { !$0.content.isEmpty }
            .map { (role: $0.role.rawValue, content: $0.content) }
        let systemBase = config.systemPrompt
        let wantsPage = includePage

        streamTask = Task { [weak self] in
            guard let self else { return }

            var system = systemBase
            if wantsPage, let page = await self.pageSnapshot() {
                system += """

                The user is on this page:
                Title: \(page.title)
                URL: \(page.url)

                \"\"\"
                \(page.text)
                \"\"\"
                """
            }

            do {
                let prepared = try AssistantService.prepare(
                    provider: provider,
                    messages: history,
                    system: system
                )
                for try await delta in AssistantService.stream(prepared) {
                    switch delta {
                    case .text(let chunk):
                        self.append(chunk, to: assistantID)
                    case .reasoning(let chunk):
                        self.appendReasoning(chunk, to: assistantID)
                    }
                }
            } catch is CancellationError {
                // user pressed stop
            } catch let error as URLError where error.code == .cancelled {
                // user pressed stop
            } catch {
                let description: String
                if let urlError = error as? URLError {
                    description = "\(urlError.localizedDescription) [\(urlError.code.rawValue)] — \(provider.baseURL)"
                } else {
                    description = error.localizedDescription
                }
                self.fail(description, id: assistantID)
            }

            self.isStreaming = false
            self.streamTask = nil
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    private func append(_ delta: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += delta
    }

    private func appendReasoning(_ delta: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].reasoning += delta
    }

    private func fail(_ message: String, id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].error = message
    }

    private func pageSnapshot() async -> (title: String, url: String, text: String)? {
        guard let tab = tabManager.selectedTab else { return nil }
        let webView = tab.webView
        let script = """
        JSON.stringify({
          title: document.title,
          url: location.href,
          text: (document.body ? document.body.innerText : '').slice(0, 16000)
        })
        """
        do {
            let raw = try await webView.evaluateJavaScript(script)
            guard
                let string = raw as? String,
                let data = string.data(using: .utf8),
                let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return (
                dict["title"] as? String ?? "",
                dict["url"] as? String ?? "",
                dict["text"] as? String ?? ""
            )
        } catch {
            return nil
        }
    }
}
