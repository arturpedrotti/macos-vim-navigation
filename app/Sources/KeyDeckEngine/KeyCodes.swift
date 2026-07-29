import Foundation
import CoreGraphics
import KeyDeckCore

/// Virtual keycode ↔ key-name mapping for the native engine.
///
/// `KeyDeckCore.KeyNames` owns the canonical keyCode → name table (it is shared
/// with the shortcut recorder and the config format). This adds the reverse
/// direction, which the engine needs to turn a configured binding like
/// `{mods: ["ctrl"], key: "="}` into something it can compare an event against.
public enum KeyCodes {
    /// name → US-ANSI virtual keycode. Built once by inverting the core table.
    public static let byName: [String: CGKeyCode] = {
        var out: [String: CGKeyCode] = [:]
        for (code, name) in KeyNames.byKeyCode { out[name] = CGKeyCode(code) }
        return out
    }()

    public static func keyCode(for name: String) -> CGKeyCode? {
        byName[name.lowercased()]
    }

    public static func name(for keyCode: CGKeyCode) -> String? {
        KeyNames.byKeyCode[Int(keyCode)]
    }

    // MARK: modifiers

    /// The four modifiers the config can name, and the flag each one sets.
    public static let modifierFlag: [String: CGEventFlags] = [
        "cmd": .maskCommand, "alt": .maskAlternate,
        "ctrl": .maskControl, "shift": .maskShift,
    ]

    /// Virtual keycode → the *sided* modifier name it represents. The tap
    /// activator has to tell right-Option from left-Option, so every modifier
    /// event is resolved to exactly one sided name (never both "alt" and
    /// "rightAlt", which would fire a tap handler twice per release).
    public static let sidedModifierName: [CGKeyCode: String] = [
        56: "leftShift", 60: "rightShift",
        59: "leftCtrl",  62: "rightCtrl",
        58: "leftAlt",   61: "rightAlt",
        55: "leftCmd",   54: "rightCmd",
    ]

    /// "rightAlt" → "alt": the flag a sided modifier name still sets.
    public static func baseModifier(_ name: String) -> String {
        var n = name
        for prefix in ["left", "right"] where n.hasPrefix(prefix) {
            n = String(n.dropFirst(prefix.count))
        }
        return n.prefix(1).lowercased() + n.dropFirst()
    }

    /// The subset of `flags` we care about — macOS sets device-dependent bits
    /// (and `maskNonCoalesced`) that must be masked off before comparing.
    public static let relevantMask: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift,
    ]

    public static func flags(for mods: [String]) -> CGEventFlags {
        var f: CGEventFlags = []
        for m in mods { if let flag = modifierFlag[baseModifier(m)] { f.insert(flag) } }
        return f
    }

    /// True when an event is exactly this binding: same key, same modifiers, no extras.
    public static func matches(_ binding: KeyBinding, code: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard !binding.key.isEmpty, let wanted = byName[binding.key.lowercased()] else { return false }
        return wanted == code && flags.intersection(relevantMask) == KeyCodes.flags(for: binding.mods)
    }
}
