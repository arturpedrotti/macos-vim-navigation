import Foundation
import AppKit
import ApplicationServices

/// Accessibility permission — the one thing macOS will not let any keyboard tool
/// skip. KeyDeck needs exactly this one permission and nothing else: no full
/// disk access, no input monitoring, no helper daemon, no third-party app.
public enum Permissions {
    /// Whether this process may create an event tap right now.
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Ask macOS to show the "grant access" prompt. The system remembers the
    /// answer per app bundle, so the user is asked at most once.
    @discardableResult
    public static func request() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Deep-link straight to the right pane — the fallback when the prompt was
    /// dismissed earlier and macOS won't show it again.
    public static func openSystemSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
