import Foundation
import ServiceManagement

/// "Open at login", via `SMAppService` — the modern API, which needs no helper
/// bundle, no privileged install step and no user trip through System Settings.
///
/// A keyboard layer that disappears on reboot is worse than useless, so this is
/// on by default: `ensureDefaultEnabled()` registers on the very first launch
/// and then never overrides the user's own choice again.
enum LoginItem {
    private static let defaultsKey = "keydeck.loginItem.initialized"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Turn it on once, the first time this Mac runs KeyDeck.
    static func ensureDefaultEnabled() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultsKey) else { return }
        defaults.set(true, forKey: defaultsKey)
        setEnabled(true)
    }
}
