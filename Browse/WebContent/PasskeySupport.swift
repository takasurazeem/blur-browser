import Foundation
import OSLog
import Security
import WebKit

/// Decides whether pages see WebAuthn (passkeys, security keys).
///
/// In a third-party `WKWebView` every WebAuthn request, including security keys
/// and the phone/QR flow, goes through macOS's AuthenticationServicesAgent. The
/// agent refuses any app not signed with Apple's managed
/// `com.apple.developer.web-browser.public-key-credential` entitlement
/// ("Client tried to use web-browser-only options … not properly entitled"),
/// so the request fails instantly. Sites read that failure as a device
/// problem; Google, for example, says "Make sure Bluetooth is on".
///
/// Without the entitlement we turn WebAuthn off, so `PublicKeyCredential` is
/// undefined and sites go straight to their fallbacks: password, a phone
/// prompt, or "try another way". A build signed with the granted profile
/// gets WebAuthn back on its own. See docs/passkeys.md.
@MainActor
enum PasskeySupport {
    static let entitlement = "com.apple.developer.web-browser.public-key-credential"

    /// Whether this process's signature carries the passkey entitlement.
    static let isAvailable: Bool = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) else {
            return false
        }
        return (value as? Bool) ?? false
    }()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Blur-Browser", category: "Passkeys")
    private static var didLog = false

    static func configure(_ preferences: WKPreferences) {
        if !didLog {
            didLog = true
            if isAvailable {
                logger.notice("Passkeys enabled: signed with \(entitlement, privacy: .public)")
            } else {
                logger.notice("Passkeys: missing \(entitlement, privacy: .public); WebAuthn \(WebExtensionManager.hasSavedExtensions ? "left on for extensions" : "hidden so sites fall back", privacy: .public)")
            }
        }
        // Password-manager extensions (1Password) supply passkeys by wrapping
        // navigator.credentials, so leave WebAuthn visible when any extension
        // is installed; their fallback just fails like before.
        guard !isAvailable, !WebExtensionManager.hasSavedExtensions else { return }
        setFeature("WebAuthenticationEnabled", enabled: false, in: preferences)
    }

    /// WebKit's internal feature flags are only reachable through SPI
    /// (`+[WKPreferences _features]`, `-_setEnabled:forFeature:`).
    private static func setFeature(_ key: String, enabled: Bool, in preferences: WKPreferences) {
        let featuresSelector = NSSelectorFromString("_features")
        let setSelector = NSSelectorFromString("_setEnabled:forFeature:")
        guard WKPreferences.responds(to: featuresSelector),
              preferences.responds(to: setSelector),
              let features = (WKPreferences.self as AnyObject).perform(featuresSelector)?.takeUnretainedValue() as? [NSObject],
              let feature = features.first(where: { ($0.value(forKey: "key") as? String) == key }) else {
            logger.error("WebKit feature \(key, privacy: .public) not found; WebAuthn left as is")
            return
        }
        typealias SetEnabled = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        let implementation = unsafeBitCast(preferences.method(for: setSelector), to: SetEnabled.self)
        implementation(preferences, setSelector, enabled, feature)
    }
}
