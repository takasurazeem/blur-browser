# Web extensions

Blur-Browser hosts web extensions through WebKit's own API
(`WKWebExtensionController`, `WKWebExtensionContext`, `WKWebExtension`;
macOS 15.4+). It's the same engine Safari uses, so extensions get the
`browser.*`/`chrome.*` APIs Safari supports: MV2 and MV3, service-worker
backgrounds, content scripts, `tabs`, `windows`, `storage`, `action`,
`scripting`, declarativeNetRequest, and native messaging.

## Using it

**Extensions** menu:

- **Import from Chrome, Arc or Brave…**: lists extensions already installed
  in Chromium browser profiles on this Mac (any `…/Extensions/<id>/<version>`
  under `~/Library/Application Support`) and loads a copy. This is the easy
  way to get 1Password.
- **Load Unpacked Extension…**: pick a folder that contains `manifest.json`.
  Like Chrome extensions installed from Chrome, it's copied (see below).
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
| Chrome import, managed copies, compat shim | `Browse/Extensions/ChromeExtensionImporter.swift`, `Browse/Extensions/blur-chrome-compat.js` |
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

## Chrome compatibility shim

Unpacked extensions are copied to
`~/Library/Application Support/Blur-Browser/Extensions/<install id>/` (Chrome's
`_metadata/` dropped, `manifest.json` `key` kept, so the Chrome ID is
unchanged). `blur-chrome-compat.js` is then put in front of the background
script:

- **MV3:** a sibling `blur-<worker>.js` holds the shim followed by the original
  worker, and the manifest points at it.
- **MV2:** the shim is prepended to `background.scripts`.

The shim adds stand-ins for Chrome APIs WebKit lacks: `notifications`,
`downloads`, `idle`, `management`, `privacy`, `storage.managed`, and missing
events such as `webNavigation.onCreatedNavigationTarget`, `tabs.onReplaced`
and `runtime.onSuspend`. Without it 1Password's worker dies on its first line
(`chrome.notifications.onClicked`).

Two WebKit quirks found on the way:

- **Additions to API objects can vanish.** WebKit's namespace objects
  (`chrome.webNavigation`, …) are wrappers that can be garbage-collected and
  recreated, and anything added to them is lost. The shim keeps references
  (`globalThis.__blurChromeCompatKeepAlive`) to every object it extends.
- **Error positions in big minified workers are unreliable.** The line/column
  of a background error can point at the top-level call into an async
  initializer, and the quoted expression can be the wrong one. Log with
  `console.error` (it shows up in `WKWebExtensionContext.errors`) to find the
  real failure.

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

Status (2026-10-19, 1Password 8.12.40 desktop, extension 8.12.41.1):

| Step | State |
|---|---|
| Chrome extension imported, Chrome ID `aeblfdkhhhdcdjpifhhbdiojplfjncoa` kept | Done (Extensions › Import…, from Arc/BrowserClaw's profile) |
| Background worker starts under WebKit | Done, with the compat shim |
| Native host found and launched (`com.1password.1password` → `1Password-BrowserSupport`, origin passed as `argv[1]`) | Done |
| Extension ↔ host messaging | Works. First request `NmRequestAccounts`; reply `NotificationModern / BrowserVerificationFailed (UnknownBrowser)` |
| Browser added in 1Password › Settings › Browser | Done by you; reply changed from `UnknownBrowser` to `BrowserSignatureInvalid` |
| 1Password accepts the signature | **No: needs a Developer ID signature** (below) |
| Popup locked/unlocked, password fill, passkey on webauthn.io | Not verified yet; blocked on the signature |

**Why the Safari version can't be used:** "1Password for Safari" reaches the
desktop app through an app extension that only Safari may host. The Chrome
extension uses a standard native-messaging host instead, which this browser
can launch.

**How 1Password decides whether to trust a browser:** `1Password-BrowserSupport`
checks the code signature of the process that launched it (our app). Browsers
you add under **Settings › Browser** must satisfy this requirement, found in
the helper binary:

```
anchor apple generic and (
  certificate leaf[field.1.2.840.113635.100.6.1.9]      // Mac App Store
  or certificate leaf[field.1.2.840.113635.100.6.1.3]
  or certificate leaf[field.1.2.840.113635.100.6.1.6]
  or certificate leaf[field.1.2.840.113635.100.6.1.25.1]
  or certificate 1[field.1.2.840.113635.100.6.2.6]
     and certificate leaf[field.1.2.840.113635.100.6.1.13]  // Developer ID Application
) and certificate leaf[subject.OU] = "<team id>"
```

**Apple Development certificates aren't on the list**, so a Debug build is
answered `BrowserSignatureInvalid`. `codesign -v -R='<that requirement>'`
fails for our Apple Development build and passes for Arc and Brave. Dropping
`get-task-allow` doesn't help; the certificate type is what matters.
Notarization isn't part of the check.

### Your steps

1. **Create a Developer ID Application certificate** (Account Holder of team
   `95B9YTC3G2`): Xcode › Settings › Accounts › add that Apple ID if missing ›
   select the team › **Manage Certificates…** › **+** › **Developer ID
   Application**. Or developer.apple.com › Certificates › + › Developer ID
   Application, with a CSR from Keychain Access. Check it with:

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

2. **Build and install with it:**

   ```bash
   scripts/install-app.sh
   ```

   It builds Release, signs with your Developer ID certificate, replaces
   /Applications/Blur-Browser.app and launches it. Use this copy day to day.
   Debug builds from Xcode stay Apple Development and won't connect to
   1Password.
3. **Re-add the browser** in 1Password › Settings › Browser: remove the old
   Blur-Browser entry, add /Applications/Blur-Browser.app again, approve, unlock.
4. Click the 1Password toolbar button in Blur-Browser.

To watch what 1Password answers (message types and status codes only, never
content):

```bash
/usr/bin/log stream --level debug --predicate 'subsystem == "com.takasurazeem.blur-browser" AND category == "NativeMessaging"'
```

- `BrowserVerificationFailed/UnknownBrowser`: not added in 1Password.
- `BrowserVerificationFailed/BrowserSignatureInvalid`: added, but not signed
  with Developer ID.
- Account and item traffic: connected.

### Passkeys through 1Password

1Password saves and fills passkeys itself. Its page script
(`inline/injected/webauthn-listeners.js`, `world: MAIN`) wraps
`navigator.credentials.create/get`. That route doesn't need Apple's passkey
entitlement, but it only installs if `navigator.credentials` exists. So
`PasskeySupport` leaves WebAuthn visible whenever any extension is installed,
and only hides it when there are none. When 1Password declines a request,
it falls back to the browser's own WebAuthn, which still fails without the
entitlement (see [passkeys.md](passkeys.md)).

### Known overlap

Blur-Browser's built-in password manager (`passwordManager.js`) still runs
alongside 1Password, so both may offer to save or fill. Turn one off if
that's noisy.
