import SwiftUI

@MainActor
struct AssistantSettingsView: View {
    let store: AssistantStore
    @Binding var isPresented: Bool

    @State private var draft: AssistantConfig

    init(store: AssistantStore, isPresented: Binding<Bool>) {
        self.store = store
        self._isPresented = isPresented
        self._draft = State(initialValue: store.config)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Assistant providers")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach($draft.providers) { $provider in
                        providerEditor($provider)
                    }
                }
                .padding(12)
            }

            Divider()

            HStack {
                Button("Add provider") {
                    draft.providers.append(
                        AssistantProvider(
                            label: "New provider",
                            kind: .openai,
                            baseURL: AssistantProviderKind.openai.defaultBaseURL,
                            model: AssistantProviderKind.openai.defaultModel
                        )
                    )
                }
                Spacer()
                Button("Save") {
                    store.apply(draft)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 640, height: 600)
        .background(Color(nsColor: Colors.chromeBg))
    }

    @ViewBuilder
    private func providerEditor(_ provider: Binding<AssistantProvider>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                TextField("Label", text: provider.label)
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive) {
                    let id = provider.wrappedValue.id
                    draft.providers.removeAll { $0.id == id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }

            Picker("Kind", selection: provider.kind) {
                ForEach(AssistantProviderKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Base URL", text: provider.baseURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            HStack(spacing: 8) {
                TextField("Model", text: provider.model)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                SecureField("API key", text: provider.apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Use this provider") {
                    draft.activeProviderID = provider.wrappedValue.id
                }
                .controlSize(.small)

                Spacer()

                if draft.activeProviderID == provider.wrappedValue.id {
                    Text("Active")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(nsColor: Colors.accentPrimary))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: Colors.foregroundPrimary).opacity(0.05))
        )
    }
}
