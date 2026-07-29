import Foundation

/// Pure mapping between AppKit key events and the key names used in the config
/// file. Kept free of AppKit so it is unit-testable; the shortcut recorder feeds
/// it raw keyCode / modifierFlags values, and `KeyDeckEngine.KeyCodes` inverts
/// the table to match live events.
public enum KeyNames {
    /// US ANSI virtual keycode → key name. Deterministic regardless of the active
    /// keyboard layout's produced characters.
    public static let byKeyCode: [Int: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
        36: "return", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "space", 50: "`",
        51: "delete", 53: "escape", 117: "forwarddelete",
        123: "left", 124: "right", 125: "down", 126: "up",
        115: "home", 116: "pageup", 119: "end", 121: "pagedown",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7",
        100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
        105: "f13", 107: "f14", 113: "f15", 106: "f16", 64: "f17", 79: "f18", 80: "f19", 90: "f20",
    ]

    /// Resolve a key name from a keyCode, falling back to the typed character.
    public static func keyName(forKeyCode keyCode: Int, characters: String? = nil) -> String? {
        if let n = byKeyCode[keyCode] { return n }
        if let c = characters, !c.isEmpty { return c.lowercased() }
        return nil
    }

    // NSEvent.ModifierFlags raw masks (avoids importing AppKit here).
    private static let shiftMask: UInt   = 1 << 17
    private static let controlMask: UInt = 1 << 18
    private static let optionMask: UInt  = 1 << 19
    private static let commandMask: UInt = 1 << 20

    /// Map raw NSEvent modifier flags to config modifier names (ctrl, alt, shift, cmd).
    public static func modifierNames(rawFlags: UInt) -> [String] {
        var mods: [String] = []
        if rawFlags & controlMask != 0 { mods.append("ctrl") }
        if rawFlags & optionMask  != 0 { mods.append("alt") }
        if rawFlags & shiftMask   != 0 { mods.append("shift") }
        if rawFlags & commandMask != 0 { mods.append("cmd") }
        return mods
    }

    /// True if the keyCode is a bare modifier key (no useful binding on its own).
    public static func isModifierKeyCode(_ keyCode: Int) -> Bool {
        // left/right shift, control, option, command, caps, fn.
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }
}
