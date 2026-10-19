# AI browsing agent

First slice of an agent that drives navigation and browsing. Open it with **⌥⌘A**
(View → Toggle Agent) or the sparkles button in the toolbar.

## Pieces

| Area | Files |
|---|---|
| Panel (right side, shares the edge with History) | `Browse/Agent/Views/AgentPanelView.swift`, hosted in `MainSplitViewController` |
| Agent loop | `Browse/Agent/AgentController.swift` |
| Tools over `TabManager` / `WKWebView` | `Browse/Agent/Tools/AgentTools.swift` |
| Permission model + consent log | `Browse/Agent/Permissions/AgentPermissions.swift` |
| Model providers | `Browse/Agent/Provider/` (`ModelProvider` protocol, `ClaudeProvider`, `KeychainStore`) |
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
`AgentContentBlock`) and the tool definitions, and returns the next assistant turn.
Wire formats stay inside each provider.

`ClaudeProvider` calls `POST https://api.anthropic.com/v1/messages` over URLSession,
since Swift has no official SDK and the project takes no third-party dependencies.

- The default model is `claude-opus-5-5`, with `output_config.effort: "medium"`. You
  can switch to Sonnet 5.5 or Haiku 5.5 in Settings → AI.
- Server-side refusal fallback is on (`fallbacks: "default"`, beta
  `server-side-fallback-2026-07-01`) for the models that support it.
- The transcript is append-only. Assistant turns are stored exactly as returned,
  including `thinking` blocks, which are kept as `.opaque` and sent back unchanged.
  Every `tool_use` gets a `tool_result`, even when the run is cancelled.
- The API key lives in the Keychain: generic password, service `Blur-Browser.AI`,
  account `anthropic-api-key`, `WhenUnlockedThisDeviceOnly`. It's read for each
  request and never stored in UserDefaults or files. You enter it in Settings → AI.

To add a provider, conform to `ModelProvider` and return it from
`AISettings.makeProvider()`.

### Debug-only scripted provider

Debug builds launched with `BLUR_AGENT_PROVIDER=scripted` use `ScriptedProvider`. It
handles one request, "open ‹domain› and tell me the heading", with no API key, so you
can test the loop, tools and approval cards. It isn't compiled into Release builds.

## Not in this slice

- Streaming responses, conversation persistence, and a history of past runs.
- Element targeting inside iframes and shadow DOM. `read_page` only sees the top
  document.
- Per-site grants that outlive the window session, and a settings list for revoking
  grants mid-session. Closing the window clears them.
- Other providers, such as OpenAI-compatible or local models. The `feat/native-assistant`
  branch has a multi-provider chat pane that could adopt `ModelProvider`.
