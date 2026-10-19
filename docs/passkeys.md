# Passkeys and code signing

Passkeys (WebAuthn) in a `WKWebView` browser depend on one managed entitlement:

```xml
<key>com.apple.developer.web-browser.public-key-credential</key>
<true/>
```

Apple grants it per team, and it only works when a provisioning profile that
contains it signs the app. Upstream's profile ("Blur3", team `9PYC9KWKRS`)
belongs to the original author. A fork can't sign with it, which is why Google
passkey sign-in fails in fork builds.

## How signing is set up

Signing settings are no longer hard-coded in the project. They come from
`Config/Signing.xcconfig`, which the Blur-Browser target uses as its base
configuration:

| | Debug | Release |
|---|---|---|
| Entitlements | `Browse/Resources/Browse.Debug.entitlements` (no managed key) | `Browse/Resources/Browse.entitlements` (passkey key) |
| Identity | `-` (ad-hoc, "Sign to Run Locally") | `Developer ID Application` |
| Profile | none | `Blur3` |
| Team / bundle id | upstream's | upstream's |

`Signing.xcconfig` keeps upstream's values. It ends with
`#include? "Signing.local.xcconfig"`, an optional, gitignored file where a
fork sets its own team. Without that file Debug still builds, ad-hoc signed,
on any Mac.

### Use your own team

```bash
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
```

Then edit it:

```
BLUR_DEVELOPMENT_TEAM = <your 10-character Team ID>
BLUR_BUNDLE_IDENTIFIER = com.<you>.blur-browser
BLUR_SIGN_IDENTITY_Debug = Apple Development
```

Your Team ID is the `OU=` of your certificate. This command lists it:

```bash
security find-identity -v -p codesigning
```

Check what Xcode will use:

```bash
xcodebuild -project Blur-Browser.xcodeproj -scheme Blur-Browser -configuration Debug -showBuildSettings | grep -E " (DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_IDENTITY|CODE_SIGN_ENTITLEMENTS) ="
```

Debug signs with your Apple Development certificate and needs no provisioning
profile, because `Browse.Debug.entitlements` has no restricted keys. A real
signature with a team ID matters for more than passkeys: 1Password refuses
ad-hoc-signed browsers (see [extensions.md](extensions.md)).

> Changing the bundle id gives the app a fresh `~/Library` container, so
> history, pinned tabs and website data start empty under the new id.

## Getting the passkey entitlement

For this fork: team **`95B9YTC3G2`**, bundle id **`com.takasurazeem.blur-browser`**.

1. **Sign Xcode in to the team.** In Xcode › Settings › Accounts, add the
   Apple ID that owns team `95B9YTC3G2`. As of 2026-10-19 Xcode on this Mac
   only knows the free Personal Team (`E2D87XL9X7`), so it can't create
   profiles for `95B9YTC3G2`.
2. **Register the App ID.** At developer.apple.com › Certificates, IDs &
   Profiles › Identifiers › **+** › App IDs › App, choose platform **macOS**
   and an **Explicit** Bundle ID of `com.takasurazeem.blur-browser`.
3. **Request the entitlement (Account Holder only).** Open
   <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential>
   and follow its link to the dedicated request form. The general "additional
   capabilities" form is the wrong one. Other roles get an access error.
   - Team ID `95B9YTC3G2`, bundle id `com.takasurazeem.blur-browser`.
   - Describe it as a general-purpose macOS web browser built on WebKit
     (`WKWebView`). It handles `http`/`https`, can be the default browser, and
     users sign in to arbitrary sites, so it needs WebAuthn/passkeys for any
     relying party.
4. **Wait for Apple's email.** Reports range from days to weeks.

### After the grant

1. Identifiers › `com.takasurazeem.blur-browser` › **Capabilities** (or
   **Additional Capabilities**): turn on the web browser public key credential
   capability and save. It only appears once the grant reaches the team.
2. Register this Mac under Devices if it isn't already. The ID to enter:

   ```bash
   system_profiler SPHardwareDataType | grep "Provisioning UDID"
   ```

3. Profiles › **+** › **macOS App Development** › App ID
   `com.takasurazeem.blur-browser` › certificate "Apple Development: Takasur
   Azeem (5SSRYGQ62H)" › this Mac. Name it `Blur Browser Passkeys Dev`, then
   download and double-click it. For builds you give to other people, also
   make a **Developer ID** profile; that needs a Developer ID Application
   certificate.
4. In `Config/Signing.local.xcconfig`, sign Debug with the profile and the
   managed entitlements:

   ```
   BLUR_PROFILE_Debug = Blur Browser Passkeys Dev
   BLUR_ENTITLEMENTS_Debug = Browse/Resources/Browse.entitlements
   ```

   Release, with a Developer ID profile:

   ```
   BLUR_SIGN_IDENTITY_Release = Developer ID Application
   BLUR_PROFILE_Release = <Developer ID profile name>
   BLUR_ENTITLEMENTS_Release = Browse/Resources/Browse.entitlements
   ```

5. Rebuild and check:

   ```bash
   codesign -d --entitlements - build/DerivedData/Build/Products/Debug/Blur-Browser.app
   ```

   It should list `com.apple.application-identifier`
   (`95B9YTC3G2.com.takasurazeem.blur-browser`) and
   `com.apple.developer.web-browser.public-key-credential`. On launch the app
   logs `Passkeys enabled`:

   ```bash
   /usr/bin/log show --last 5m --predicate 'category == "Passkeys"'
   ```

6. Test at <https://webauthn.io>. Register should show the system passkey
   sheet with iCloud Keychain, "iPhone, iPad or Android device" (QR), and
   security key. Then try Google.

Nothing in code needs to change after the grant. `PasskeySupport` turns
WebAuthn back on when the running app has the entitlement.

## Before the grant: what was measured

Tested 2026-10-19 on macOS 27 with the user's Debug build and two signed
probe apps. Evidence is from `log show`.

| Build | Agent's answer | Result in the page |
|---|---|---|
| Team-signed, no provisioning profile (the normal Debug build) | "Attempted to perform authorization from process without application identifier." | `NotAllowedError` |
| Same, with WebKit's own authenticator stack (`WebAuthenticationASEnabled` off) | Same refusal: that stack goes through the same agent ("Could not connect to authorization daemon") | `NotAllowedError` |
| Signed with a Mac development profile, so it has `com.apple.application-identifier` | "Client tried to use web-browser-only options … not associated with domain webauthn.io … not properly entitled for this request. Rejecting." | `NotAllowedError` |

So in a third-party `WKWebView` app, **every** WebAuthn path goes through
AuthenticationServicesAgent and is refused without the managed entitlement:
iCloud Keychain passkeys, the phone/QR (hybrid) flow, and USB/NFC security
keys. The system sheet never appears.

- **Google's "Make sure Bluetooth is on" is misleading.** Google shows it
  whenever the WebAuthn call fails. Bluetooth is never reached. Safari has no
  `NSBluetoothAlwaysUsageDescription` either, because the hybrid flow's
  Bluetooth work happens in system daemons. The app isn't sandboxed, so
  `com.apple.security.device.bluetooth` does nothing. Info.plist now has
  `NSBluetoothAlwaysUsageDescription` anyway, for the post-grant flow in case
  macOS asks, but it doesn't change the result before the grant.
- **What the app does now:** `Browse/WebContent/PasskeySupport.swift` checks
  the running app's signature. Without the entitlement it turns off WebKit's
  `WebAuthenticationEnabled`, so pages see no `PublicKeyCredential` and skip
  straight to their fallbacks (password, Google's phone prompt, "try another
  way") instead of a broken passkey prompt. The app logs
  `Passkeys disabled: missing …` once at launch.
- **Associated domains don't help a browser.** With an application
  identifier, the agent would accept a site only if the app listed it under
  `webcredentials:` and the site's `apple-app-site-association` file named
  the app. That's impossible for arbitrary sites like Google.
- **Real alternatives, not built:**
  - Implement CTAP2 over USB HID ourselves (what Chrome and Firefox do on
    macOS) and bridge it into the page with an injected
    `navigator.credentials` shim. That gets security keys working without
    Apple. It's a large job: CTAP framing, CBOR, and the PIN protocol for
    user verification.
  - The phone/QR flow would also need caBLE v2 (BLE advertising, a tunnel
    service, and the Noise handshake), which is much larger.
  - `ASWebAuthenticationSession` runs Safari's stack, but its cookies land in
    Safari's store, so the tab doesn't come out signed in.
