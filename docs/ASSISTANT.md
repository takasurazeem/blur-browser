# Assistant pane (Sidecar)

A native AI pane inside Blur-Browser, added on `feat/native-assistant`.

- Toggle: **⌘⇧Y** (View → Toggle Assistant)
- Right-hand pane, hosted the same way as the history panel
- Streaming chat against OpenAI-compatible, Anthropic, and Gemini endpoints
- Page context read from the active tab's `WKWebView`

## Providers

Stored in `~/Library/Application Support/Blur-Browser/assistant.json` (mode 0600).
Defaults: local Nemotron MoE (`:8080`), vLLM hyper-qwen (`:18020`), OpenAI, Anthropic, Gemini.

## Local model access (important)

macOS Local Network privacy blocks **unsigned** apps from reaching `192.168.x.x`; the
failure surfaces as `NSURLErrorDomain -1009` ("The Internet connection appears to be
offline") with `unsatisfied (Local network prohibited)` in `log show`.

For a local debug build, sign ad-hoc (drops the restricted passkey entitlement, which
requires a provisioning profile):

```bash
xcodebuild -project Blur-Browser.xcodeproj -scheme Blur-Browser -configuration Debug \
  -derivedDataPath /tmp/blur-build \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-" CODE_SIGN_ENTITLEMENTS="" build
open /tmp/blur-build/Build/Products/Debug/Blur-Browser.app
```

On first request macOS should ask to allow local network access. If it does not:
**System Settings → Privacy & Security → Local Network → Blur-Browser → on**, then relaunch.

`NSLocalNetworkUsageDescription` is set in `Browse/Resources/Info.plist`, and ATS allows
arbitrary loads because a browser must reach arbitrary origins.

## Not in this slice

No agent tools (click/type/navigate) and no permission modes yet — chat, page context,
and provider switching only.
