# Web extensions

Blur-Browser hosts web extensions through WebKit's own API
(`WKWebExtensionController`, `WKWebExtensionContext`, `WKWebExtension`;
macOS 15.4+). It's the same engine Safari uses, so extensions get the
`browser.*`/`chrome.*` APIs Safari supports: MV2 and MV3, service-worker
backgrounds, content scripts, `tabs`, `windows`, `storage`, `action`,
`scripting`, declarativeNetRequest, and native messaging.

## Using it

**Extensions** menu:

- **Load Unpacked Extension…**: pick a folder that contains `manifest.json`.
- **Load Safari Extension from App…**: pick an app (or an `.appex`). Each
  Safari web extension in its `Contents/PlugIns` is loaded, using only the
  extension's resources. See the limits below.
- **Remove Extension ›**: unloads it and forgets it.

On install the browser shows one prompt listing the requested permissions and
host patterns. Accepting grants all of them, and they are re-granted on later
launches. Permissions an extension requests later (`permissions.request`,
optional hosts) get their own Allow / Don't Allow prompt.

Extensions with a toolbar action get a button in their own Liquid Glass
capsule, to the left of [reload · share · focus]. The button shows the
action's icon and badge for the selected tab. Clicking it runs the action and
opens the popup, if there is one, in a popover under the button.

Sample: `Extensions/Samples/hello-blur`. It has a popup that reads the active
tab, a content script it messages, a badge with the tab count, and storage.
In Debug builds you can load it for one run without the menu:

```bash
open -n path/to/Blur-Browser.app --args -BlurLoadExtension "$PWD/Extensions/Samples/hello-blur"
```

In Debug, extension pages are inspectable: Safari › Develop › Blur-Browser.

## How it's wired

| Piece | File |
|---|---|
| Controller, install/restore, delegate | `Browse/Extensions/WebExtensionManager.swift` |
| `WKWebExtensionTab` / `WKWebExtensionWindow` adapters over `BrowserTab` / `BrowserWindowController` | `Browse/Extensions/WebExtensionAdapters.swift` |
| Native messaging (Chrome-style stdio hosts) | `Browse/Extensions/NativeMessagingBridge.swift` |
| Toolbar buttons + popover anchor | `Browse/Toolbar/AddressBarViewController.swift` |
| Controller attached to every tab's configuration | `BrowserTab.makeFilterConfiguration()` |

- `TabManager` stays the single source of truth. The window's 50 ms polling
  loop calls `WebExtensionManager.syncTabs(for:)`, which diffs the tab list,
  selection and per-tab url/title/loading/pinned state. It then reports
  `didOpenTab`, `didCloseTab`, `didActivateTab`, `didMoveTab` and
  `didChangeTabProperties` to WebKit.
- Extension calls that change tabs (`tabs.create`, `update`, `remove`,
  `pinned`) go back through `TabManager` methods.
- The controller uses a persistent configuration (identifier kept in
  `UserDefaults`), and each install keeps a stable `uniqueIdentifier`. Together
  they make extension storage and `webkit-extension://` origins survive
  relaunches.

## Native messaging

`runtime.sendNativeMessage` and `runtime.connectNative` go to Chrome-format
native messaging hosts. Hosts are looked up in this order:

1. `~/Library/Application Support/Blur-Browser/NativeMessagingHosts/<name>.json`
2. `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/<name>.json`
3. `/Library/Google/Chrome/NativeMessagingHosts/<name>.json`

Apps that registered a host for Chrome are found with no setup. As in Chrome,
the host's `allowed_origins` must list the caller, `chrome-extension://<id>/`.
The ID is computed from the manifest's `key` exactly as Chrome does it. The
host is started with that origin as `argv[1]` and speaks length-prefixed JSON
over stdio.

## Limits

- **Safari extensions loaded from another app don't get native messaging.**
  A Safari web extension's native side is an app extension that only Safari
  may host (`com.apple.Safari.web-extension`). A third-party browser can load
  the extension's JS/HTML but can't reach its handler. Extensions that are
  pure JS work. Ones that depend on their containing app don't.
- `chrome.*`-only APIs Safari lacks (`offscreen`, `sidePanel`, `identity`,
  `debugger`, …) aren't there. WebKit reports unsupported manifest keys in
  `WKWebExtension.errors`.
- No private windows, tab groups, or multi-selection; `tabs.highlight`
  selects a single tab.

## 1Password

**Short answer:** not out of the box. There's a realistic path, but only you
can finish it, because it needs 1Password's extension files and your 1Password
app's approval. Here is what 1Password checks and what is in place for each.

1Password's browser integration has two parts, and both have to accept the
browser:

1. **The extension.** For Safari, 1Password ships "1Password for Safari", a
   separate App Store app whose Safari web extension talks to 1Password through
   its app extension. As described under Limits, Blur-Browser can load that
   extension's files but can't reach its native side. **Use the Chrome
   extension instead** (Web Store ID `aeblfdkhhhdcdjpifhhbdiojplfjncoa`). It
   talks to 1Password through a standard native messaging host.
2. **The native messaging host.** 1Password 8 registers
   `com.1password.1password` for Chrome and other browsers. The manifest is
   already in `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
   on this Mac. Its executable is
   `/Applications/1Password.app/Contents/Library/LoginItems/1Password Browser Helper.app/Contents/MacOS/1Password-BrowserSupport`,
   and its `allowed_origins` include `chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/`.
   Blur-Browser's bridge finds this host automatically.
3. **The browser check.** This is the real gate. 1Password inspects the
   process that launched the host (the browser) and verifies its code
   signature. The 1Password 8.12 binaries contain a built-in allowlist of
   browsers by bundle id and team id, plus "custom browsers" a user adds
   under **1Password › Settings › Browser**. They also contain the errors this
   check produces: `BrowserVerificationFailed`, `UnknownBrowser`, "The selected
   application was not signed…", and "…signed in an unsupported way or may be
   missing a required identifier". Per 1Password staff on their community
   forum, ad-hoc-signed apps are rejected and the check can't be bypassed. The
   `custom_allowed_browsers` file only works on Linux.

### Steps to try

1. Sign the browser with your team. Set up `Config/Signing.local.xcconfig` as
   described in [passkeys.md](passkeys.md). The browser must carry a team ID
   and bundle identifier. An ad-hoc Debug build will be refused.
2. Build, copy `Blur-Browser.app` to **/Applications** (1Password staff list
   this as a requirement for custom browsers), and launch it from there.
3. In **1Password › Settings › Browser**, add `/Applications/Blur-Browser.app`
   as a browser. If 1Password says the app "was signed in an unsupported way",
   it is rejecting the Apple Development signature. Sign with a Developer ID
   certificate instead, and notarize the build if needed.
4. Get an unpacked copy of the 1Password Chrome extension that keeps its
   Chrome ID:
   - Install it in Chrome, then copy
     `~/Library/Application Support/Google/Chrome/Default/Extensions/aeblfdkhhhdcdjpifhhbdiojplfjncoa/<version>/`
     somewhere stable. Chrome writes the extension's `key` into that
     `manifest.json`, so Blur-Browser computes the same ID and the host's
     `allowed_origins` check passes.
   - Remove `_metadata/` from the copy (Chrome's signature data).
5. **Extensions › Load Unpacked Extension…** → that folder.
6. Open the 1Password popup from the toolbar. If it reaches the host, the
   desktop app asks you to approve the new browser.

### Unverified, may block it

- Whether 1Password's custom-browser check accepts an **Apple Development**
  signature or requires **Developer ID**.
- Whether 1Password's MV3 Chrome extension runs under WebKit's extension API.
  It may use Chrome-only APIs such as `offscreen`; check the extension's
  errors in Safari › Develop. If it does, it won't work in any WebKit browser,
  this one included.
- None of the 1Password flow was exercised here. It needs your 1Password app
  and approval prompts. What was tested: the sample extension end-to-end
  (popup, `tabs`, `storage`, content-script messaging, badge) through WebKit's
  API, and the bridge's stdio framing against a test host.

If this path fails, try 1Password's macOS-level autofill (1Password ›
Settings › Autofill, the system AutoFill provider). It doesn't need the
extension, but it hasn't been checked whether it offers suggestions inside a
third-party `WKWebView`.
