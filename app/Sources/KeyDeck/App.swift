import SwiftUI
import AppKit
import KeyDeckCore
import KeyDeckEngine

/// KeyDeck runs as a menu-bar app: the engine lives in this process, so there is
/// nothing to install, nothing to reload, and closing the window doesn't stop
/// your shortcuts working.
@main
struct KeyDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("KeyDeck", id: "main") {
            MainView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 560)
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra {
            MenuBarMenu(model: model) { openWindow(id: "main") }
        } label: {
            // Filled while Nav Mode is live, so the menu bar always answers
            // "am I in the mode?" even if the overlay is off-screen.
            Image(systemName: model.isNavActive ? "keyboard.fill" : "keyboard")
        }
    }
}

/// Menu-bar contents: state at a glance, and the two things worth doing without
/// opening the window.
private struct MenuBarMenu: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    var body: some View {
        Text(model.statusLine)
        Divider()
        Button(model.isNavActive ? "Leave Nav Mode" : "Enter Nav Mode") { model.toggleNav() }
            .disabled(model.engineState != .running)
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit KeyDeck") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Keeps the app alive with no windows open — the settings window is a visitor,
/// the engine is the product.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.ensureDefaultEnabled()
        // A menu-bar app is not activated on launch, so its window would open
        // behind whatever the user was doing. Bring it forward the first time —
        // but not on a login-item launch, where silence is the point.
        guard !isLoginLaunch(notification) else { return }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    /// True when macOS launched us at login rather than the user opening the app.
    private func isLoginLaunch(_ notification: Notification) -> Bool {
        // NSApplicationLaunchIsDefaultLaunchKey — false means launched by the
        // system (login item, reopen) rather than by the user.
        (notification.userInfo?["NSApplicationLaunchIsDefaultLaunchKey"] as? Bool) == false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
