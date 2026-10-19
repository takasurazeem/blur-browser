import SwiftUI

@MainActor
struct AssistantPane: View {
    @Bindable var store: AssistantStore
    var onClose: () -> Void

    @State private var draft = ""
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color(nsColor: Colors.borderLight))
            conversation
            Divider().overlay(Color(nsColor: Colors.borderLight))
            composer
        }
        .background(Color(nsColor: Colors.chromeBg))
        .sheet(isPresented: $showSettings) {
            AssistantSettingsView(store: store, isPresented: $showSettings)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: Colors.accentPrimary))
                .frame(width: 8, height: 8)

            Text("Sidecar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))

            Spacer(minLength: 4)

            Picker("", selection: Binding(
                get: { store.config.activeProviderID },
                set: { store.selectProvider($0) }
            )) {
                ForEach(store.config.providers) { provider in
                    Text(provider.model.isEmpty ? provider.label : provider.model)
                        .tag(provider.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 150)
            .controlSize(.small)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .help("Assistant settings")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close assistant")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if store.messages.isEmpty {
                        emptyState
                    }
                    ForEach(store.messages) { message in
                        messageView(message)
                            .id(message.id)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: store.messages.last?.content) { _, _ in
                scrollToEnd(proxy)
            }
            .onChange(of: store.messages.last?.reasoning) { _, _ in
                scrollToEnd(proxy)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask your own model")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))

            Text("This pane talks straight to the endpoint you pick. With page context on, it reads the visible text of the current tab.")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                suggestion("Summarize this page in five bullets", "Summarize this page in five bullets.")
                suggestion("What are the key claims here?", "What are the key claims on this page, and what evidence supports them?")
                suggestion("Pull out action items", "Pull out every action item, date, and name from this page.")
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }

    private func suggestion(_ title: String, _ prompt: String) -> some View {
        Button {
            store.send(prompt)
        } label: {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: Colors.foregroundPrimary).opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func messageView(_ message: AssistantMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 30)
                Text(message.content)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: Colors.foregroundPrimary).opacity(0.08))
                    )
            }

        case .assistant:
            VStack(alignment: .leading, spacing: 5) {
                Text((store.activeProvider?.model ?? "model").uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))

                if message.content.isEmpty && message.error == nil {
                    if message.reasoning.isEmpty {
                        Text("…")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                    } else {
                        Text(String(message.reasoning.suffix(700)))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                            .lineLimit(12)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    markdown(message.content)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = message.error {
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func markdown(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Toggle(isOn: $store.includePage) {
                    Label("Page", systemImage: "globe")
                        .font(.system(size: 10.5))
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Spacer()

                Text(store.activeProvider?.model ?? "no model")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                    .lineLimit(1)
            }

            HStack(alignment: .bottom, spacing: 7) {
                TextField("Ask anything…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .lineLimit(1...5)
                    .onSubmit(submit)

                Button {
                    if store.isStreaming {
                        store.stop()
                    } else {
                        submit()
                    }
                } label: {
                    Image(systemName: store.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(nsColor: Colors.foregroundInverse))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle().fill(Color(nsColor: store.isStreaming ? Colors.foregroundMuted : Colors.accentPrimary))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!store.isStreaming && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: Colors.foregroundPrimary).opacity(0.06))
            )
        }
        .padding(10)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = store.messages.last else { return }
        withAnimation(.easeOut(duration: 0.1)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func submit() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        store.send(text)
    }
}
