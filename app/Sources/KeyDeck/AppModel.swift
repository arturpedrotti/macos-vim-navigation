import SwiftUI
import Combine
import KeyDeckCore
import KeyDeckEngine

/// Single source of truth for the UI: the config being edited, the engine that
/// runs it, license state, and permission status.
///
/// There is no Apply button and no reload step. Editing the config mutates the
/// running engine immediately and persists it on a short debounce, because the
/// engine lives in this process — the whole apply / reload / heartbeat-verify
/// dance the Hammerspoon-backed version needed is gone.
@MainActor
final class AppModel: ObservableObject {
    @Published var config: Config {
        didSet {
            guard config != oldValue else { return }
            engine.apply(config)          // instant: the running engine is right here
            schedulePersist()
        }
    }
    @Published private(set) var engineState: EngineState = .stopped
    @Published private(set) var isNavActive = false
    @Published private(set) var saveError: String?
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            if let err = LoginItem.setEnabled(launchAtLogin) { saveError = err }
        }
    }

    let license = LicenseManager()
    private let engine = Engine.shared
    private var persistTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var permissionPoll: Timer?
    private static let debounceNanos: UInt64 = 500_000_000

    init() {
        config = ConfigStore.load()
        launchAtLogin = LoginItem.isEnabled

        engine.apply(config)
        engine.start()

        // Mirror engine state into properties the views observe.
        engine.$state.sink { [weak self] in self?.engineState = $0 }.store(in: &cancellables)
        engine.$isNavActive.sink { [weak self] in self?.isNavActive = $0 }.store(in: &cancellables)

        // If permission was granted while the app was closed, start as soon as
        // the user comes back to the window.
        if engine.state == .needsPermission { startPermissionPolling() }
    }

    // MARK: derived state

    var tier: Tier { license.state.tier }
    var conflicts: [BindingConflict] { Validation.conflicts(in: config) }
    var canAddLauncher: Bool {
        Entitlements.canAddLauncher(currentCount: config.apps.count, tier: tier)
    }
    var needsPermission: Bool { engineState == .needsPermission }

    var statusLine: String {
        switch engineState {
        case .running:         return isNavActive ? "Nav Mode is on" : "KeyDeck is active"
        case .needsPermission: return "Needs Accessibility"
        case .stopped:         return "KeyDeck is off"
        case .failed(let msg): return msg
        }
    }

    /// Cheat sheet preview for the settings window — the same data the in-mode
    /// `?` overlay renders, so the two can never disagree.
    var cheatSheet: [HUDSection] { NavMode.cheatSheet(config: config) }

    // MARK: actions

    func toggleNav() { engine.toggleNav() }

    /// The one-click setup path: ask macOS for Accessibility, then watch for the
    /// answer so the engine starts the moment the box is ticked. The user never
    /// has to come back and press anything else.
    func requestPermission() {
        Permissions.request()
        Permissions.openSystemSettings()
        startPermissionPolling()
    }

    private func startPermissionPolling() {
        permissionPoll?.invalidate()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                guard Permissions.isTrusted else { return }
                timer.invalidate()
                self.permissionPoll = nil
                self.engine.restart()
            }
        }
    }

    // MARK: persistence

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceNanos)
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    /// Write the config to disk. A conflicted config is never written — the
    /// inline warnings stand until it's resolved — but the engine already holds
    /// it in memory, so the user can still see what their edit does. The refusal
    /// is surfaced via `saveError`: silently skipping the write would lose the
    /// edits on quit with no warning at all.
    func persistNow() {
        persistTask?.cancel()
        guard conflicts.isEmpty else {
            saveError = "Settings not saved — resolve the duplicate key bindings first."
            return
        }
        do {
            try ConfigStore.save(config.curated())
            saveError = nil
        } catch {
            saveError = "Couldn't save settings: \(error.localizedDescription)"
        }
    }
}
