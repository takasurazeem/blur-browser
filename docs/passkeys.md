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

1. **Account Holder only.** Only the team's Account Holder can submit
   Apple's request form. Admins and Developers get an access error.
2. Open the entitlement's documentation page and follow its link to the
   dedicated request form:
   <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential>
   (the general "additional capabilities" request form is the wrong one).
3. Describe the app as a general-purpose macOS web browser: it handles
   `http`/`https`, can be set as the default browser, and lets users browse
   arbitrary sites. Give the bundle id you put in `Signing.local.xcconfig`.
4. Wait for approval. Reports vary from days to weeks.

### After the grant

1. In **Certificates, Identifiers & Profiles → Identifiers**, open your App ID
   (the bundle id above). Under **Additional Capabilities**, turn on the web
   browser public key credential capability. It only appears once the grant
   reaches your team.
2. Create a **Developer ID** provisioning profile for that App ID, for
   distribution outside the App Store. For local testing, also create a
   **macOS App Development** profile that includes your Mac. Download and
   double-click both.
3. Point Release, and optionally Debug, at the managed entitlements and the
   profile in `Config/Signing.local.xcconfig`:

   ```
   BLUR_SIGN_IDENTITY_Release = Developer ID Application
   BLUR_PROFILE_Release = <Developer ID profile name>
   BLUR_ENTITLEMENTS_Release = Browse/Resources/Browse.entitlements

   // To test passkeys in Debug too:
   // BLUR_SIGN_IDENTITY_Debug = Apple Development
   // BLUR_PROFILE_Debug = <macOS App Development profile name>
   // BLUR_ENTITLEMENTS_Debug = Browse/Resources/Browse.entitlements
   ```

4. Confirm the signed app carries the key:

   ```bash
   codesign -d --entitlements - path/to/Blur-Browser.app
   ```

5. Test at <https://webauthn.io>, then with a Google account that has a
   passkey.

## What works before the grant

Expect **none of WebAuthn to work** in an app without the entitlement. That
covers iCloud Keychain passkeys, the phone/QR ("hybrid") flow, and USB/NFC
security keys alike.

On current macOS, WebKit hands every `navigator.credentials.create/get` call
to AuthenticationServices. AuthenticationServices only presents its sheet for
Safari or for apps holding this entitlement. Without it, sites get a
`NotAllowedError`, and the system logs `ASAuthorizationError` 1004 ("Told not
to present authorization sheet"). Developers on Apple's forums report that
security keys failed the same way and started working once the entitlement was
granted.

- **Bluetooth isn't the blocker.** The hybrid flow's Bluetooth work happens in
  system daemons, not in the browser process, and the app isn't sandboxed, so
  `com.apple.security.device.bluetooth` changes nothing. The missing
  entitlement stops the sheet from appearing at all.
- **Passwords still work.** Sites that offer a password or "try another way"
  fall back fine. 1Password's extension may also be able to fill passkeys
  itself once it's connected (see [extensions.md](extensions.md)).
- **Possible stopgap, not built:** for a single sign-in, open it in
  `ASWebAuthenticationSession`, which runs Safari's authentication stack with
  passkey support. Cookies from that session land in Safari's store, not
  `WKWebsiteDataStore.default()`, so the tab doesn't come out signed in. That
  makes it a poor fit for general browsing.

To check this on your own build, open <https://webauthn.io> in a Debug build
and register. A failure that shows `NotAllowedError` confirms the gate.
