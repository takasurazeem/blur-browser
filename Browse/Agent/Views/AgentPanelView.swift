import SwiftUI

/// Right-side agent panel: chat, inline approval cards, permission mode.
/// Hosted by `MainSplitViewController` the same way as the history panel.
struct AgentPanelView: View {
    let controller: AgentController
    var onDismiss: () -> Void

    @State private var draft = ""
    @State private var showConsent = false
    @State private var hasAPIKey = AISettings.hasAPIKey
    @FocusState private var composerFocused: Bool

    private var session: AgentSession { controller.session }
    private var isDangerous: Bool { session.mode == .dangerous }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isDangerous { dangerBanner }
            transcript
            composer
        }
        .sheet(isPresented: $showConsent) {
            AgentConsentSheet(
                onConfirm: { acknowledgement in
                    session.enableDangerousMode(acknowledgement: acknowledgement)
                    showConsent = false
                },
                onCancel: { showConsent = false }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiSettingsDidChange)) { _ in
            hasAPIKey = AISettings.hasAPIKey
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Label("Agent", systemImage: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
            Spacer()
            modeMenu
            iconButton("square.and.pencil", help: "New Conversation") {
                controller.resetConversation()
            }
            iconButton("xmark", help: "Close Agent", action: onDismiss)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var modeMenu: some View {
        Menu {
            Button {
                session.disableDangerousMode()
            } label: {
                Label("Ask before acting", systemImage: isDangerous ? "hand.raised" : "checkmark")
            }
            Button {
                if !isDangerous { showConsent = true }
            } label: {
                Label("Dangerous — never ask…", systemImage: isDangerous ? "checkmark" : "exclamationmark.triangle")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isDangerous ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                Text(isDangerous ? "Dangerous" : "Ask")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isDangerous ? Color.white : Color(nsColor: Colors.foregroundSecondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassEffect(isDangerous ? .regular.tint(SettingsColors.danger).interactive() : .regular.interactive(), in: Capsule())
        .help("Permission mode for this window")
    }

    private var dangerBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Dangerous mode: the agent acts without asking in this window until you switch back or quit.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Stop") { session.disableDangerousMode() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white)
        .padding(10)
        .glassEffect(.regular.tint(SettingsColors.danger), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if controller.items.isEmpty { emptyState }
                    ForEach(controller.items) { item in
                        row(for: item).id(item.id)
                    }
                    if controller.isRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Working…")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                        }
                        .id("working")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: controller.items.count) {
                withAnimation(.smooth(duration: 0.2)) {
                    proxy.scrollTo(controller.isRunning ? AnyHashable("working") : AnyHashable(controller.items.last?.id), anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask the agent to browse for you.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
            Text("It reads pages freely, and asks before it navigates, clicks, types or submits — unless you allow a site for this session or turn on Dangerous mode.")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                .fixedSize(horizontal: false, vertical: true)
            if !hasAPIKey {
                Button("Add an API key in Settings → AI") { SettingsWindowController.shared.showSettings(tab: .ai) }
                    .buttonStyle(.glassProminent)
                    .tint(SettingsColors.accent)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func row(for item: AgentChatItem) -> some View {
        switch item.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 32)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(SettingsColors.accent), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .assistant(let text):
            Text(LocalizedStringKey(text))
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .action(let info):
            AgentActionCard(info: info) { choice in
                controller.resolveApproval(itemID: item.id, choice: choice)
            }
        case .notice(let text, let isError):
            Label(text, systemImage: isError ? "exclamationmark.circle" : "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(isError ? SettingsColors.danger : Color(nsColor: Colors.foregroundMuted))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask the agent…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                .lineLimit(1...5)
                .focused($composerFocused)
                .onSubmit(submit)
                .padding(.vertical, 2)
            Button(action: controller.isRunning ? controller.stop : submit) {
                Image(systemName: controller.isRunning ? "stop.fill" : "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(SettingsColors.accent))
            }
            .buttonStyle(.plain)
            .disabled(!controller.isRunning && draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .help(controller.isRunning ? "Stop" : "Send")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(10)
    }

    private func submit() {
        guard !controller.isRunning else { return }
        controller.send(draft)
        draft = ""
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .help(help)
    }
}

// MARK: - Action card

/// One tool call. While awaiting approval it shows Allow / Allow on site / Deny.
struct AgentActionCard: View {
    let info: AgentChatItem.ActionInfo
    let onDecide: (AgentApprovalChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: info.risk.symbol)
                    .foregroundStyle(riskColor)
                Text(info.summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusView
            }
            if info.status == .awaitingApproval {
                Text("\(info.risk.label)\(info.host.map { " on \($0)" } ?? "") — allow?")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                HStack(spacing: 6) {
                    Button("Allow") { onDecide(.allowOnce) }
                        .buttonStyle(.glassProminent)
                        .tint(SettingsColors.accent)
                    if let host = info.host {
                        Button("Allow on \(host)") { onDecide(.allowSiteForSession) }
                            .buttonStyle(.glass)
                            .help("Allow \(info.risk.label.lowercased()) actions on \(host) without asking, for this window session")
                    }
                    Button("Deny", role: .destructive) { onDecide(.deny) }
                        .buttonStyle(.glass)
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var riskColor: Color {
        switch info.risk {
        case .readOnly, .navigation: Color(nsColor: Colors.foregroundMuted)
        case .pageMutating: SettingsColors.accent
        case .formSubmit: SettingsColors.danger
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch info.status {
        case .awaitingApproval:
            Image(systemName: "questionmark.circle.fill").foregroundStyle(SettingsColors.accent)
        case .running:
            ProgressView().controlSize(.mini)
        case .done(let allowedBy):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SettingsColors.allowGreen)
                .help(allowedBy.map { "Ran without asking: \($0)" } ?? "Done")
        case .denied:
            Text("Denied").font(.system(size: 11, weight: .semibold)).foregroundStyle(SettingsColors.denyRed)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SettingsColors.denyRed)
                .help(message)
        }
    }
}

// MARK: - Consent sheet

/// The only way to turn on Dangerous mode. Confirming writes a consent record
/// (timestamp, window session id, mode, the statement below) to the log.
struct AgentConsentSheet: View {
    static let acknowledgement = "I understand the agent will navigate, click, type and submit forms in this window without asking me, and that a website's content could try to steer it. I can switch back to Ask at any time; this resets when I quit."

    let onConfirm: (String) -> Void
    let onCancel: () -> Void
    @State private var agreed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Turn on Dangerous mode?", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SettingsColors.danger)

            VStack(alignment: .leading, spacing: 6) {
                bullet("The agent stops asking before it navigates, clicks, types or submits forms.")
                bullet("Applies only to this window, until you switch back or quit.")
                bullet("Web pages can contain text written to mislead an AI. Without prompts, nothing stops it acting on that.")
                bullet("Your consent is recorded with a timestamp in a local log.")
            }

            Toggle(isOn: $agreed) {
                Text(Self.acknowledgement)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)

            HStack {
                Text(AgentConsentLog.fileURL.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Turn On") { onConfirm(Self.acknowledgement) }
                    .buttonStyle(.glassProminent)
                    .tint(SettingsColors.danger)
                    .disabled(!agreed)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
    }
}

extension Notification.Name {
    static let aiSettingsDidChange = Notification.Name("aiSettingsDidChange")
}
