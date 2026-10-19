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
| 1Password trusts Blur-Browser | **Needs you:** add the browser in 1Password (below) |
| Popup locked/unlocked, password fill, passkey on webauthn.io | Not verified yet; needs the step above |

**Why the Safari version can't be used:** "1Password for Safari" reaches the
desktop app through an app extension that only Safari may host. The Chrome
extension uses a standard native-messaging host instead, which this browser
can launch.

**How 1Password decides whether to trust a browser:** `1Password-BrowserSupport`
checks the code signature of the process that launched it (our app). The
desktop app keeps a built-in list of trusted browsers (bundle id + team id)
and also accepts browsers the user adds under **Settings › Browser**. Its
errors include `BrowserVerificationFailed`, `UnknownBrowser`, "The selected
application was not signed…" and "…signed in an unsupported way or may be
missing a required identifier". Ad-hoc-signed builds are always refused.
Blur-Browser in /Applications is signed "Apple Development: Takasur Azeem",
team `95B9YTC3G2`, bundle id `com.takasurazeem.blur-browser`. Whether
1Password accepts an Apple Development signature (vs Developer ID) is what
the next step shows.

### Your steps

1. Use **/Applications/Blur-Browser.app**, the one that's installed there. To
   update it after a rebuild:

   ```bash
   ditto build/DerivedData/Build/Products/Debug/Blur-Browser.app /Applications/Blur-Browser.app
   ```

2. 1Password › **Settings › Browser** → add **/Applications/Blur-Browser.app**.
   It may be called "Add Browser" or "Connect additional browsers".
3. In Blur-Browser, click the 1Password toolbar button. If 1Password asks
   you to approve the browser connection, approve it, then unlock.
4. If step 2 says the app "was signed in an unsupported way", 1Password wants
   a Developer ID signature. Create a Developer ID Application certificate
   (developer.apple.com › Certificates › + › Developer ID Application, Account
   Holder only), then set `BLUR_SIGN_IDENTITY_Debug = Developer ID Application`
   in `Config/Signing.local.xcconfig`, rebuild, copy to /Applications, and add
   it again.

To watch what 1Password answers (message types only, never content):

```bash
/usr/bin/log stream --level debug --predicate 'subsystem == "com.takasurazeem.blur-browser" AND category == "NativeMessaging"'
```

`BrowserVerificationFailed` means 1Password doesn't trust the browser yet.
Account and item traffic means it's connected.

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
