# AI browsing agent

The browser's one AI pane, on the right. It drives navigation and browsing with
tool-capable models, and works as page-aware chat with models that can't call tools.
Open it with **⌥⌘A** (View → Toggle Agent) or the sparkles button in the toolbar.

It replaces the separate Assistant pane (⌘⇧Y) from `feat/native-assistant`. That
pane's providers are now `ModelProvider`s, its settings moved to Settings → AI, and
its API keys moved into the Keychain (see "Migration from the Assistant pane").

## Pieces

| Area | Files |
|---|---|
| Panel (right side, shares the edge with History) | `Browse/Agent/Views/AgentPanelView.swift`, hosted in `MainSplitViewController` |
| Agent loop | `Browse/Agent/AgentController.swift` |
| Tools over `TabManager` / `WKWebView` | `Browse/Agent/Tools/AgentTools.swift` |
| Permission model + consent log | `Browse/Agent/Permissions/AgentPermissions.swift` |
| Model providers | `Browse/Agent/Provider/` (`ModelProvider` protocol, `ClaudeProvider`, `OpenAICompatibleProvider`, `GeminiProvider`, `AIProviderStore`, `KeychainStore`) |
| Local-network relay | `tools/relay.py` |
| Settings → AI | `Browse/Settings/AISettingsView.swift` |

## Tools and risk levels

Every tool declares a risk level. The level decides whether it needs approval.

| Risk | Tools | Asks in Ask mode? |
|---|---|---|
| Read-only | `list_tabs`, `read_page`, `scroll` | Never |
| Navigation | `open_url`, `new_tab`, `switch_tab`, `go_back`, `go_forward` | Yes |
| Page-mutating | `click`, `type_text` | Yes |
| Form-submit | `type_text` with `submit: true`; `click` on a submit button | Yes |

A tool's risk can only go up at runtime. Before asking, `click` checks the target
element, and a submit button (`<button>` in a form, `input[type=submit|image]`) makes it
**form-submit**. That way, allowing clicks on a site doesn't also allow submitting
forms there.

`scroll` counts as read-only. It changes only the viewport, sends nothing, and the
agent needs it to read long pages.

Other limits that apply in every mode:

- `open_url` and `new_tab` load only `http`/`https`. Anything without a scheme becomes
  `https://…` or a search, so `file://` and `javascript:` can't be opened.
- `type_text` refuses password fields. `read_page` lists what each field is for (label
  or placeholder), never what's typed in it.
- Page scripts run in WebKit's isolated `.defaultClient` content world, so page
  JavaScript can't change the agent's helpers.
- The page text is labelled as untrusted in the tool result. The system prompt tells
  the model to treat it as data, not instructions.
- The loop stops after 30 model steps. **Stop** cancels the run, and any approval it's
  waiting on counts as a denial.

## Permission modes

The mode belongs to the window. `AgentSession` lives on `BrowserWindowController` and
is never saved, so both modes reset on relaunch and one window's mode never affects
another.

### Ask (default)

- Read-only actions run without asking.
- Any other action shows an inline card with **Allow**, **Allow on ‹host›** and
  **Deny**.
  - **Allow** runs this one action.
  - **Allow on ‹host›** adds a grant for that host at that risk level, for this window
    session. Later actions on the host at that level or lower run without asking. A
    riskier action still asks: a navigation grant doesn't cover clicks, and a click
    grant doesn't cover form submission.
  - **Deny** returns an error to the model. It is told not to retry and to ask the
    user what to do instead.
- The host is the current tab's host for page actions, and the destination host for
  `open_url`, `new_tab` and `switch_tab`.

### Dangerous — never ask

- Every action runs without a prompt, in this window only.
- The **only** way in is the mode menu in the panel header, which opens a consent
  sheet. **Turn On** stays disabled until the user ticks the acknowledgement.
- `AgentSession.enableDangerousMode` writes the consent record first and switches the
  mode only if the write succeeded. Nothing else changes the mode to `.dangerous`.
- While it's on, a red **Dangerous** capsule shows in the toolbar next to the URL
  field, the panel shows a red banner with **Stop**, and the sparkles button turns
  red.
- To leave, switch back to Ask in the panel menu, press **Stop** on the banner, or
  quit. Switching back is logged too.

### Consent log

`~/Library/Application Support/Blur-Browser/agent-consent-log.jsonl` is append-only
JSON Lines. The file is created with mode 0600, and the app only appends to it. It
never rewrites or truncates it. Each line looks like this:

```json
{"acknowledgement":"I understand the agent will …","appVersion":"0.9.2","event":"dangerous_mode_enabled","mode":"dangerous","timestamp":"2026-10-19T17:21:43Z","windowSessionID":"95FBF432-…"}
```

`event` is `dangerous_mode_enabled` or `dangerous_mode_disabled`. `windowSessionID` is
the `AgentSession.id` of the window. **Settings → AI → Show in Finder** opens the file.

## Model providers

`ModelProvider` takes a system prompt, a provider-neutral transcript (`AgentMessage` /
`AgentContentBlock`), the tool definitions and a stream callback, and returns the next
assistant turn. Wire formats stay inside each provider. Everything is plain URLSession,
since the project takes no third-party dependencies.

| Kind | Provider | Endpoint | Tools | Streaming |
|---|---|---|---|---|
| Anthropic | `ClaudeProvider` | `POST {base}/messages` | Yes | No |
| OpenAI-compatible | `OpenAICompatibleProvider` | `POST {base}/chat/completions` (SSE) | `tools` / `tool_calls`, if enabled | Yes |
| Google Gemini | `GeminiProvider` | `POST {base}/models/{model}:streamGenerateContent?alt=sse` | `functionDeclarations`, if enabled | Yes |

"OpenAI-compatible" covers OpenAI itself and local servers: llama.cpp, vLLM, LM
Studio, Ollama, or the loopback relay below.

### Configuring providers (Settings → AI)

- `AIProviderStore` holds the list of providers and which one is active. It's saved in
  UserDefaults (`ai.providers`, `ai.activeProviderID`) and holds **no secrets**.
- Each provider has a name, type, base URL, model, a **Browser tools** switch and an
  API key. The radio button picks the active one. The pane header also has a provider
  menu for switching quickly.
- Defaults on a fresh install: Claude (`claude-opus-5-5`), OpenAI (`gpt-4.1-mini`),
  Google Gemini (`gemini-2.5-flash`) and a "Local model" at `http://127.0.0.1:8080/v1`.
- Keys are Keychain generic passwords: service `Blur-Browser.AI`,
  `WhenUnlockedThisDeviceOnly`. The built-in Claude entry uses account
  `anthropic-api-key`, as the first agent release did, so a saved key keeps working.
  Others use `provider-‹uuid›`. Deleting a provider deletes its key.
- Loopback and private-network base URLs (`localhost`, `127.x`, `10.x`, `172.16–31.x`,
  `192.168.x`, `*.local`) don't need a key. Hosted ones do.

### Browser tools on or off

With **Browser tools** on, the model gets the tools above and the permission modes
apply. With it off, the provider is chat-only: the pane hides the Ask/Dangerous menu,
shows an **Include this page** checkbox, and when it's ticked attaches the current
tab's `read_page` output to each message, labelled as untrusted. Previous tool calls
in the conversation are sent as plain text, because many servers reject `tool_calls`
in a request without `tools`.

Hosted APIs start with tools on. Local endpoints start with tools off, since tool
calling depends on the server (llama.cpp needs `--jinja`, vLLM needs a tool parser).
Turn it on if yours supports it.

### Provider notes

- **Claude.** The default model is `claude-opus-5-5`, with
  `output_config.effort: "medium"`. Effort is only sent for the 5.x models, so older
  model ids imported from the Assistant pane still work. Server-side refusal fallback
  (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`) is on for the
  models that support it, and only against `api.anthropic.com`.
- **Transcript.** The transcript is append-only. Assistant turns are stored exactly as
  returned. Every `tool_use` gets a `tool_result`, even when the run is cancelled.
- **Opaque blocks.** Provider-specific data is kept as `.opaque(vendor:)` and sent
  back unchanged. For Claude these are `thinking` blocks. For Gemini, the whole model
  turn is kept so `thoughtSignature`s go back intact. Other providers skip blocks
  from a different vendor, so you can switch models mid-conversation.
- **Gemini schemas.** Gemini takes an OpenAPI subset, so `additionalProperties` and
  empty `required` are removed, and tools with no parameters send no `parameters`.
  `functionResponse` gets the function name from the matching call.
- **Streaming.** OpenAI-compatible and Gemini responses stream into the pane. Reasoning
  is shown dimmed while the answer hasn't started: `reasoning_content`/`reasoning`
  deltas, Gemini `thought` parts, and `<think>…</think>` in the content. If the content
  only has a closing `</think>`, because the chat template opened it in the prompt,
  everything before it counts as reasoning.

To add a provider, conform to `ModelProvider`, add an `AIProviderKind` case and build
it in `AIProviderConfig.makeProvider()`.

### Migration from the Assistant pane

The Assistant pane kept providers **and API keys in plain text** in
`~/Library/Application Support/Blur-Browser/assistant.json`. On first launch,
`AIProviderStore` migrates them once:

1. Each provider is imported with the same id, name, URL and model.
2. Each non-empty key is saved to the Keychain.
3. An Anthropic entry's key goes to the built-in Claude entry if that has no key yet,
   so no duplicate is added. Otherwise it becomes its own entry.
4. Imported entries replace stock entries without a key that have the same endpoint.
5. The Assistant pane's active provider becomes the active one.
6. Only after **every** key is stored, `assistant.json` is deleted and
   `ai.migratedAssistantJSON` is set. If any Keychain write fails, nothing is
   committed and the migration runs again on the next launch.

The migration doesn't touch backups such as `assistant.json.bak`. Delete those by hand,
since they may contain keys.

### Local models

macOS Local Network privacy can block the app from reaching `192.168.x.x`. The failure
shows up as `NSURLErrorDomain -1009` with `Local network prohibited` in `log show`.
`NSLocalNetworkUsageDescription` is set in `Info.plist`, so macOS should ask on the
first request. If it doesn't, go to **System Settings → Privacy & Security → Local
Network → Blur-Browser**, turn it on, and relaunch. Unsigned builds may never be
allowed. In that case, run the loopback relay (loopback is never gated) and point the
provider at it:

```bash
python3 tools/relay.py --listen 127.0.0.1:18080 --target 192.168.1.150:8080
# base URL: http://127.0.0.1:18080/v1
```

`Info.plist` sets `NSAllowsArbitraryLoads`, so URLSession can reach `http://` model
servers on any host. Web content is still loaded by WebKit.

### Debug-only scripted provider

Debug builds launched with `BLUR_AGENT_PROVIDER=scripted` use `ScriptedProvider`. It
handles one request, "open ‹domain› and tell me the heading", with no API key, so you
can test the loop, tools and approval cards. It isn't compiled into Release builds.

## Not in this slice

- Streaming for Claude (it uses the non-streaming Messages API), conversation
  persistence, and a history of past runs.
- Element targeting inside iframes and shadow DOM. `read_page` only sees the top
  document.
- Per-site grants that outlive the window session, and a settings list for revoking
  grants mid-session. Closing the window clears them.
- Custom system prompt and temperature, which the Assistant pane had. Its stored
  values aren't migrated. Each mode uses a built-in prompt and the provider's default
  temperature.
