import Foundation
import AppKit
import KeyDeckCore

/// Launches or focuses an app for a Nav Mode launcher key.
///
/// This is the feature that makes Nav Mode worth entering: one bare letter, no
/// modifier, and you are in the app — which is exactly the shortcut space a
/// modal layer buys you.
@MainActor
public enum Launcher {
    /// Activate `shortcut`'s app: raise it if running, launch it otherwise, then
    /// optionally park the pointer in its window per `clickTarget`.
    public static func activate(_ shortcut: AppShortcut) {
        if let running = runningApp(for: shortcut) {
            running.unhide()
            running.activate(options: [.activateAllWindows])
            positionPointer(in: running, target: shortcut.clickTarget, delay: 0.12)
            return
        }
        guard let url = appURL(for: shortcut) else {
            HUD.shared.flash("Couldn't find \(label(for: shortcut))")
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { app, _ in
            guard let app, shortcut.clickTarget != "none" else { return }
            DispatchQueue.main.async { positionPointer(in: app, target: shortcut.clickTarget, delay: 1.2) }
        }
    }

    /// Non-isolated so the cheat sheet can be built off the main actor.
    public nonisolated static func label(for shortcut: AppShortcut) -> String {
        shortcut.names.first ?? shortcut.bundleID
    }

    // MARK: locating the app

    private static func runningApp(for shortcut: AppShortcut) -> NSRunningApplication? {
        if !shortcut.bundleID.isEmpty,
           let a = NSRunningApplication.runningApplications(withBundleIdentifier: shortcut.bundleID).first {
            return a
        }
        return NSWorkspace.shared.runningApplications.first { app in
            guard let name = app.localizedName else { return false }
            return shortcut.names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    private static func appURL(for shortcut: AppShortcut) -> URL? {
        if !shortcut.bundleID.isEmpty,
           let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: shortcut.bundleID) {
            return u
        }
        for name in shortcut.names {
            for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
                let path = "\(dir)/\(name).app"
                if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
            }
        }
        return nil
    }

    // MARK: pointer placement

    /// Put the pointer where the user will want to click next: the middle of the
    /// window, or near the bottom (chat apps, where the input box lives).
    /// Uses the Accessibility API, which we already hold permission for.
    private static func positionPointer(in app: NSRunningApplication, target: String, delay: TimeInterval) {
        guard target != "none" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let frame = focusedWindowFrame(pid: app.processIdentifier) else { return }
            let point = target == "bottom"
                ? CGPoint(x: frame.midX, y: frame.maxY - 72)
                : CGPoint(x: frame.midX, y: frame.midY)
            Pointer.move(to: point)
            Pointer.click()
        }
    }

    /// Frame of the app's main window in CG coordinates, via AXUIElement.
    private static func focusedWindowFrame(pid: pid_t) -> CGRect? {
        let axApp = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if AXUIElementCopyAttributeValue(axApp, attribute as CFString, &windowRef) == .success,
               windowRef != nil { break }
        }
        guard let window = windowRef else { return nil }
        let axWindow = window as! AXUIElement

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, let sizeValue = sizeRef
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: origin, size: size)   // AX already uses CG coordinates
    }
}
