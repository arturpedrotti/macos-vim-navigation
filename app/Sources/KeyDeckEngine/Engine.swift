import Foundation
import AppKit
import CoreGraphics
import KeyDeckCore

/// Observable engine state for the UI. Deliberately tiny — the UI shows a dot
/// and a reason, nothing more.
public enum EngineState: Equatable {
    case stopped
    case needsPermission
    case running
    case failed(String)
}

/// The native KeyDeck engine.
///
/// One `CGEventTap` at the session level watches keyDown / keyUp / flagsChanged.
/// While Nav Mode is off it is a pure observer — every event is passed through
/// untouched except the one that activates the mode. While Nav Mode is on it
/// consumes keys and turns them into pointer, scroll, click, display and
/// launcher actions.
///
/// This replaces the Hammerspoon Spoon that earlier versions shipped: no
/// external app, no Lua, no config file reload — `apply(_:)` swaps the live
/// config in place.
@MainActor
public final class Engine: ObservableObject {
    public static let shared = Engine()

    @Published public private(set) var state: EngineState = .stopped
    @Published public private(set) var isNavActive = false

    public private(set) var config: Config = .default

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let repeater = Repeater()

    /// `gg` double-tap tracking.
    private var pendingG = false
    private var gDeadline: Date = .distantPast

    /// Modifier tap-and-release tracking, shared by the Nav Mode activator and
    /// the display cycle. A "clean tap" means the modifier went down and came
    /// back up with no other key pressed in between — that is what lets ⌥ still
    /// work in ⌥⌘J while a bare ⌥ tap does something of its own.
    private var modifierTaps = ModifierTapTracker()
    private var lastKeyPressAt: Date = .distantPast
    private var lastModifierTapAt: Date = .distantPast

    private init() {}

    // MARK: lifecycle

    /// Install the event tap. Idempotent; reports why it couldn't start rather
    /// than failing silently.
    public func start() {
        guard tap == nil else { return }
        guard Permissions.isTrusted else {
            state = .needsPermission
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<Engine>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated { engine.handle(type: type, event: event) }
        }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            state = .failed("macOS refused the keyboard tap. Re-grant Accessibility and try again.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = source
        state = .running
    }

    public func stop() {
        exitNav()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        state = .stopped
    }

    public func restart() {
        stop()
        start()
    }

    /// Swap in a new configuration. Takes effect on the next keystroke — there
    /// is nothing to reload and no process to restart.
    public func apply(_ newConfig: Config) {
        config = newConfig
        if isNavActive && !newConfig.features.nav.enabled { exitNav() }
    }

    // MARK: event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that runs too slowly or when the user switches
        // fast-user-switching sessions. Re-arm instead of dying quietly.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
            return Unmanaged.passUnretained(event)   // modifiers are never swallowed
        case .keyDown:
            markKeyActivity()
            return handleKeyDown(event) ? nil : Unmanaged.passUnretained(event)
        case .keyUp:
            return handleKeyUp(event) ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Any real keypress cancels every pending "clean modifier tap".
    private func markKeyActivity() {
        lastKeyPressAt = Date()
        modifierTaps.keyPressed()
    }

    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if isNavActive {
            // The engine drives its own repeat timers, so OS auto-repeats are
            // dropped rather than double-firing every action.
            if isRepeat { return true }
            return handleNavKey(code: code, flags: flags)
        }

        // Not in Nav Mode: the only key we care about is the activator.
        guard config.features.nav.enabled else { return false }
        let activator = config.features.nav.activator
        if activator.kind == "hotkey" || activator.kind == "hyper" {
            if KeyCodes.matches(activator.hotkey, code: code, flags: flags) {
                enterNav()
                return true
            }
        } else if activator.kind == "capsLock" {
            if code == 79, flags.intersection(KeyCodes.relevantMask).isEmpty {   // F18
                enterNav()
                return true
            }
        }
        return false
    }

    private func handleKeyUp(_ event: CGEvent) -> Bool {
        guard isNavActive else { return false }
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        repeater.stop(keyCode: code)
        return true
    }

    // MARK: Nav Mode

    private func handleNavKey(code: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let name = KeyCodes.name(for: code) else { return true }
        let mods = modifierNames(from: flags)

        // A pending `gg`: a second g scrolls to the top, anything else cancels.
        if pendingG {
            pendingG = false
            if name == "g" && mods.isEmpty && Date() < gDeadline {
                Pointer.scroll(dy: 1_000_000)
                return true
            }
        }
        if name == "g" && mods.isEmpty {
            pendingG = true
            gDeadline = Date().addingTimeInterval(0.35)
            return true
        }

        // The activator toggles the mode back off, so the same key both enters
        // and leaves — no separate "how do I get out" to learn.
        let activator = config.features.nav.activator
        if (activator.kind == "hotkey" || activator.kind == "hyper"),
           KeyCodes.matches(activator.hotkey, code: code, flags: flags) {
            exitNav()
            return true
        }

        guard let action = NavMode.action(key: name, mods: mods, config: config) else {
            // Unmapped keys are swallowed on purpose: in a modal layer, a stray
            // key must never leak a character into the document underneath.
            return true
        }
        perform(action, keyCode: Int(code))
        return true
    }

    private func perform(_ action: NavAction, keyCode: Int) {
        let tuning = config.tuning
        switch action {
        case .moveFraction(let x, let y):
            repeater.start(keyCode: keyCode,
                           delay: tuning.directionInitialDelay,
                           interval: tuning.directionRepeatInterval) {
                Pointer.move(byFractionX: x, y: y)
            }
        case .scroll(let dx, let dy):
            repeater.start(keyCode: keyCode,
                           delay: tuning.scrollInitialDelay,
                           interval: tuning.scrollRepeatInterval) {
                Pointer.scroll(dx: dx, dy: dy)
            }
        case .scrollToEdge(let top):
            Pointer.scroll(dy: top ? 1_000_000 : -1_000_000)
        case .click(let count):
            Pointer.click(count: count)
        case .rightClick:
            Pointer.click(button: .right)
        case .centerPointer:
            Pointer.move(to: CGPoint(x: Displays.mainFrame.midX, y: Displays.mainFrame.midY))
        case .cycleApp(let offset):
            cycleApp(by: offset)
        case .cycleDisplay(let offset):
            Displays.cycle(by: offset, skipPattern: config.features.monitors.skipVirtualDisplayPattern)
        case .jumpDisplay(let index):
            Displays.jump(to: index, click: false,
                          skipPattern: config.features.monitors.skipVirtualDisplayPattern)
        case .toggleCheatSheet:
            HUD.shared.toggleCheatSheet(NavMode.cheatSheet(config: config))
        case .leave:
            exitNav()
        case .launch(let index):
            guard config.apps.indices.contains(index) else { return }
            let app = config.apps[index]
            // Leave the mode first: the user asked to *be in* that app, and a
            // lingering modal layer would eat their first keystrokes there.
            if app.exitNav { exitNav() }
            Launcher.activate(app)
        }
    }

    public func enterNav() {
        guard !isNavActive else { return }
        isNavActive = true
        pendingG = false
        HUD.shared.showIndicator(subtitle: "? for keys")
    }

    public func exitNav() {
        guard isNavActive else {
            HUD.shared.hideAll()
            return
        }
        isNavActive = false
        pendingG = false
        repeater.stopAll()
        HUD.shared.hideAll()
    }

    public func toggleNav() {
        isNavActive ? exitNav() : enterNav()
    }

    /// Bring the next (or previous) regular app to the front — the ⌘-tab move,
    /// available as a single key once you are already in the mode.
    private func cycleApp(by offset: Int) {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.processIdentifier) < ($1.processIdentifier) }
        guard apps.count > 1 else { return }
        let current = apps.firstIndex { $0.isActive } ?? 0
        let next = ((current + offset) % apps.count + apps.count) % apps.count
        apps[next].activate(options: [.activateAllWindows])
    }

    // MARK: modifier taps

    private func modifierNames(from flags: CGEventFlags) -> Set<String> {
        var out: Set<String> = []
        let relevant = flags.intersection(KeyCodes.relevantMask)
        for (name, flag) in KeyCodes.modifierFlag where relevant.contains(flag) { out.insert(name) }
        return out
    }

    /// Tracks clean taps of individual modifier keys, and fires the two features
    /// that ride on them: the Nav Mode tap activator and the display cycle.
    private func handleFlagsChanged(_ event: CGEvent) {
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.intersection(KeyCodes.relevantMask)

        guard let name = KeyCodes.sidedModifierName[code],
              let flag = KeyCodes.modifierFlag[KeyCodes.baseModifier(name)] else { return }

        let isDown = flags.contains(flag)
        let othersHeld = !flags.subtracting(flag).isEmpty

        if let tapped = modifierTaps.flagsChanged(name: name, isDown: isDown, othersHeld: othersHeld) {
            modifierTapped(tapped)
        }
    }

    /// A modifier was pressed and released alone. Route it to whichever feature
    /// claims it; Nav Mode wins if both want the same key.
    private func modifierTapped(_ name: String) {
        let nav = config.features.nav
        let activator = nav.activator

        if nav.enabled, activator.kind == "tapModifier" || activator.kind == "doubleTapModifier" {
            if matchesModifier(configured: activator.modifier, tapped: name) {
                if activator.kind == "doubleTapModifier" {
                    let now = Date()
                    if now.timeIntervalSince(lastModifierTapAt) < 0.35 {
                        lastModifierTapAt = .distantPast
                        toggleNav()
                    } else {
                        lastModifierTapAt = now
                    }
                } else {
                    toggleNav()
                }
                return
            }
        }

        // Display cycle on a clean tap of its modifier, guarded by a quiet
        // period so releasing ⌥ at the end of a burst of typing never yanks the
        // pointer to another screen.
        let monitors = config.features.monitors
        guard monitors.enabled, monitors.optionTapCycle, !isNavActive else { return }
        guard KeyCodes.baseModifier(name) == monitors.cycleModifier else { return }
        guard Date().timeIntervalSince(lastKeyPressAt) > config.tuning.optionReleaseIdleSeconds else { return }
        Displays.cycle(by: 1, skipPattern: monitors.skipVirtualDisplayPattern)
    }

    /// `configured` may be sided ("rightAlt") or either-side ("alt").
    private func matchesModifier(configured: String, tapped: String) -> Bool {
        if configured == tapped { return true }
        // An either-side setting matches both sided keys.
        return KeyCodes.baseModifier(configured) == configured
            && KeyCodes.baseModifier(tapped) == configured
    }
}

/// The "clean tap" state machine for sided modifier keys. Pure state, factored
/// out of the engine so the offline checks can drive it without CGEvents.
///
/// A tap is clean only if the modifier went down and came back up with nothing
/// else pressed in between — no normal key AND no other modifier. Chording is
/// symmetric: pressing a second modifier dirties every modifier already held,
/// not just the newcomer, so e.g. rightAlt↓ shift↓ shift↑ rightAlt↑ fires nothing.
struct ModifierTapTracker {
    private var down: [String: Bool] = [:]
    private var clean: [String: Bool] = [:]

    /// Any real keypress cancels every pending clean tap.
    mutating func keyPressed() {
        for key in clean.keys { clean[key] = false }
    }

    /// Feed one modifier transition. Returns the modifier's name when its
    /// release completed a clean tap, nil otherwise.
    mutating func flagsChanged(name: String, isDown: Bool, othersHeld: Bool) -> String? {
        if isDown {
            // Pressed together with another modifier — a chord: neither the new
            // key nor anything already held can be a clean tap anymore.
            if othersHeld {
                for key in down.keys where down[key] == true { clean[key] = false }
            }
            down[name] = true
            clean[name] = !othersHeld
        } else if down[name] == true {
            down[name] = false
            let wasClean = clean[name] == true
            clean[name] = false
            if wasClean { return name }
        }
        return nil
    }
}
