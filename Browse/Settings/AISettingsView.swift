import SwiftUI

/// Settings → AI: Claude API key (Keychain), model, and the consent log.
struct AISettingsView: View {
    @State private var keyDraft = ""
    @State private var hasKey = AISettings.hasAPIKey
    @State private var model = AISettings.claudeModel
    @State private var status: String?

    private static let models: [(id: String, name: String)] = [
        ("claude-opus-5-5", "Claude Opus 5.5"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-haiku-5-5", "Claude Haiku 5.5"),
    ]

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        SecureField(hasKey ? "••••••••  (saved)" : "sk-ant-…", text: $keyDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                        Button("Save", action: saveKey)
                            .buttonStyle(.glassProminent)
                            .tint(SettingsColors.accent)
                            .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        if hasKey {
                            Button("Remove", role: .destructive, action: removeKey)
                                .buttonStyle(.glass)
                        }
                    }
                } label: {
                    Text("Anthropic API key")
                    Text(status ?? "Stored in your Keychain on this Mac only. Requests go straight to api.anthropic.com.")
                }

                Picker(selection: $model) {
                    ForEach(Self.models, id: \.id) { Text($0.name).tag($0.id) }
                } label: {
                    Text("Model")
                    Text("Used by the Agent panel (⌥⌘A).")
                }
                .onChange(of: model) { _, newValue in AISettings.claudeModel = newValue }
            }

            Section {
                LabeledContent {
                    Button("Show in Finder") {
                        let url = AgentConsentLog.fileURL
                        if FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } else {
                            NSWorkspace.shared.open(url.deletingLastPathComponent())
                        }
                    }
                    .buttonStyle(.glass)
                } label: {
                    Text("Dangerous-mode consent log")
                    Text("Each time Dangerous mode is turned on or off, a record is appended here. Dangerous mode always resets when you quit.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if KeychainStore.save(key, account: KeychainStore.anthropicAccount) {
            keyDraft = ""
            hasKey = true
            status = "Saved to Keychain."
        } else {
            status = "Couldn't save to Keychain."
        }
        NotificationCenter.default.post(name: .aiSettingsDidChange, object: nil)
    }

    private func removeKey() {
        KeychainStore.delete(account: KeychainStore.anthropicAccount)
        hasKey = false
        status = "Removed."
        NotificationCenter.default.post(name: .aiSettingsDidChange, object: nil)
    }
}
