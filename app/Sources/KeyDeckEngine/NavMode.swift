import Foundation
import CoreGraphics
import KeyDeckCore

/// Everything a key can do inside Nav Mode.
///
/// Nav Mode exists to solve shortcut exhaustion: once you are in the mode, a
/// bare `j` or `s` is unclaimed by every app on the system, so a whole keyboard
/// of one-key commands opens up without fighting ⌘/⌥/⌃ for space.
public enum NavAction: Equatable {
    case moveFraction(x: CGFloat, y: CGFloat)
    case scroll(dx: Int32, dy: Int32)
    case scrollToEdge(top: Bool)
    case click(count: Int)
    case rightClick
    case centerPointer
    case cycleApp(offset: Int)
    case cycleDisplay(offset: Int)
    case jumpDisplay(index: Int)
    case toggleCheatSheet
    case leave
    case launch(index: Int)

    /// Whether holding the key should repeat the action. Movement and scrolling
    /// glide; clicks and launches must fire exactly once.
    public var repeats: Bool {
        switch self {
        case .moveFraction, .scroll: return true
        default: return false
        }
    }
}

/// Resolves a keypress to a Nav Mode action, and builds the `?` cheat sheet.
/// Pure logic — no event taps, no AppKit — so it is directly unit-testable.
public enum NavMode {
    /// Fraction of the screen a bare `hjkl` moves; shift multiplies it.
    static let smallStep: CGFloat = 1.0 / 8.0
    static let bigStep: CGFloat = 1.0 / 2.0

    /// Resolve `key` + `mods` against the built-in bindings, then the user's
    /// launchers. Built-ins win, which is why `Validation` refuses to save a
    /// launcher on a reserved key rather than letting it be silently shadowed.
    public static func action(key: String, mods: Set<String>, config: Config) -> NavAction? {
        let k = key.lowercased()
        let shift = mods.contains("shift")
        let ctrl = mods.contains("ctrl")
        let bare = mods.isEmpty
        let scrollStep = Int32(config.tuning.scrollStep)

        // Exit keys, first and unconditionally: getting out must always work.
        for binding in config.features.nav.exitKeys
        where binding.key.lowercased() == k && Set(binding.mods) == mods {
            return .leave
        }

        // Pointer movement — hjkl, plus arrow keys for anyone not yet fluent.
        let step = shift ? bigStep : smallStep
        if bare || (shift && mods.count == 1) {
            switch k {
            case "h", "left":  return .moveFraction(x: -step, y: 0)
            case "l", "right": return .moveFraction(x: step, y: 0)
            case "j":          return .moveFraction(x: 0, y: step)
            case "k":          return .moveFraction(x: 0, y: -step)
            default: break
            }
        }

        // Scrolling. shift = a page-sized jump, ctrl = a half-step.
        let multiplier: Int32 = shift ? 8 : (ctrl ? 3 : 1)
        if bare || ((shift || ctrl) && mods.count == 1) {
            switch k {
            case "d", "down": return .scroll(dx: 0, dy: -scrollStep * multiplier)
            case "u", "up":   return .scroll(dx: 0, dy: scrollStep * multiplier)
            case "w":         return .scroll(dx: -scrollStep * multiplier, dy: 0)
            case "b":         return .scroll(dx: scrollStep * multiplier, dy: 0)
            default: break
            }
        }

        // gg / G — handled here for `G`; bare `g` needs the double-tap state the
        // engine tracks, so it is resolved there. Shift must be the only
        // modifier, like every other shifted binding.
        if k == "g" && shift && mods.count == 1 { return .scrollToEdge(top: false) }

        if bare {
            switch k {
            case "space":  return .click(count: 1)
            case "i":      return .click(count: 3)   // triple-click selects the line
            case "a":      return .rightClick
            case "[":      return .cycleDisplay(offset: -1)
            case "]":      return .cycleDisplay(offset: 1)
            default: break
            }
            // 1…9 jump the pointer to that display.
            if let n = Int(k), (1...9).contains(n) { return .jumpDisplay(index: n) }
        }

        if shift && mods.count == 1 {
            switch k {
            case "space": return .click(count: 2)
            case "m":     return .centerPointer
            case "a":     return .cycleApp(offset: 1)
            case "i":     return .cycleApp(offset: -1)
            case "/":     return .toggleCheatSheet
            default: break
            }
        }

        // User launchers last.
        for (i, app) in config.apps.enumerated()
        where !app.key.isEmpty && app.key.lowercased() == k && Set(app.mods) == mods {
            return .launch(index: i)
        }
        return nil
    }

    /// The `?` cheat sheet, generated from the live config so it can never drift
    /// from what the keys actually do.
    public static func cheatSheet(config: Config) -> [HUDSection] {
        var sections: [HUDSection] = [
            HUDSection("Move pointer", [
                HUDItem("h j k l", "Move (⇧ = further)"),
                HUDItem("⇧M", "Center on screen"),
            ]),
            HUDSection("Scroll", [
                HUDItem("d / u", "Down / up"),
                HUDItem("w / b", "Left / right"),
                HUDItem("⇧d ⇧u", "Full page"),
                HUDItem("gg / G", "Top / bottom"),
            ]),
            HUDSection("Click", [
                HUDItem("space", "Click"),
                HUDItem("⇧space", "Double-click"),
                HUDItem("i", "Select line"),
                HUDItem("a", "Right-click"),
            ]),
        ]

        var windows = [HUDItem("⇧A / ⇧I", "Next / previous app")]
        if config.features.monitors.enabled {
            windows.append(HUDItem("[ / ]", "Previous / next display"))
            windows.append(HUDItem("1 2 3", "Jump to display"))
        }
        sections.append(HUDSection("Windows & displays", windows))

        let launchers = config.apps
            .filter { !$0.key.isEmpty }
            .map { HUDItem(Validation.display(mods: $0.mods, key: $0.key), Launcher.label(for: $0)) }
        if !launchers.isEmpty {
            sections.append(HUDSection("Open app", launchers))
        }
        return sections
    }
}
