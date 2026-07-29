import Foundation

// Decode helper: pull a value if present, otherwise fall back to a default. This
// mirrors the engine's deep-merge-over-defaults behavior, so a partial config
// file (or an old config still carrying removed feature blocks) loads cleanly
// into a full Config. Unknown keys are ignored by Codable.
extension KeyedDecodingContainer {
    func get<T: Decodable>(_ key: Key, default def: T) -> T {
        // `try?` flattens decodeIfPresent's `T?` to `T?`, so a single binding
        // yields the decoded value; absent/null/mismatched keys fall back to def.
        if let present = try? decodeIfPresent(T.self, forKey: key) {
            return present
        }
        return def
    }
}

/// A key + modifier combination. Named `KeyBinding` (not `Binding`) to avoid
/// colliding with SwiftUI.Binding.
public struct KeyBinding: Codable, Hashable, Sendable {
    public var mods: [String]
    public var key: String

    public init(mods: [String] = [], key: String = "") {
        self.mods = mods
        self.key = key
    }
}

extension KeyBinding {
    enum CodingKeys: String, CodingKey { case mods, key }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.mods = c.get(.mods, default: [])
        self.key = c.get(.key, default: "")
    }
}

public struct Tuning: Codable, Equatable, Sendable {
    public var scrollStep: Double
    public var scrollInitialDelay: Double
    public var scrollRepeatInterval: Double
    public var directionInitialDelay: Double
    public var directionRepeatInterval: Double
    public var optionReleaseIdleSeconds: Double
    public var optionScrollAmount: Double

    public static let `default` = Tuning(
        scrollStep: 62, scrollInitialDelay: 0.15, scrollRepeatInterval: 0.05,
        directionInitialDelay: 0.05, directionRepeatInterval: 0.15,
        optionReleaseIdleSeconds: 2.0, optionScrollAmount: 260)
}

extension Tuning {
    enum CodingKeys: String, CodingKey {
        case scrollStep, scrollInitialDelay, scrollRepeatInterval, directionInitialDelay
        case directionRepeatInterval, optionReleaseIdleSeconds, optionScrollAmount
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Tuning.default
        scrollStep = c.get(.scrollStep, default: d.scrollStep)
        scrollInitialDelay = c.get(.scrollInitialDelay, default: d.scrollInitialDelay)
        scrollRepeatInterval = c.get(.scrollRepeatInterval, default: d.scrollRepeatInterval)
        directionInitialDelay = c.get(.directionInitialDelay, default: d.directionInitialDelay)
        directionRepeatInterval = c.get(.directionRepeatInterval, default: d.directionRepeatInterval)
        optionReleaseIdleSeconds = c.get(.optionReleaseIdleSeconds, default: d.optionReleaseIdleSeconds)
        optionScrollAmount = c.get(.optionScrollAmount, default: d.optionScrollAmount)
    }
}

/// How NAV MODE is toggled. The UI only writes kind "hotkey"; the other kinds
/// remain decodable so hand-edited and pre-existing configs keep working.
/// kind: "tapModifier" | "doubleTapModifier" | "hotkey" | "hyper" | "capsLock"
public struct NavActivator: Codable, Equatable, Sendable {
    public var kind: String
    public var modifier: String
    public var onRelease: Bool
    public var hotkey: KeyBinding
    public init(kind: String, modifier: String = "rightAlt", onRelease: Bool = true,
                hotkey: KeyBinding = KeyBinding(mods: ["ctrl"], key: "=")) {
        self.kind = kind; self.modifier = modifier; self.onRelease = onRelease; self.hotkey = hotkey
    }
    public static let `default` = NavActivator(
        kind: "hotkey", modifier: "rightAlt", onRelease: true,
        hotkey: KeyBinding(mods: ["ctrl"], key: "="))
}
extension NavActivator {
    enum CodingKeys: String, CodingKey { case kind, modifier, onRelease, hotkey }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NavActivator.default
        kind = c.get(.kind, default: d.kind)
        modifier = c.get(.modifier, default: d.modifier)
        onRelease = c.get(.onRelease, default: d.onRelease)
        hotkey = c.get(.hotkey, default: d.hotkey)
    }
}

public struct NavFeature: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var activator: NavActivator
    public var exitKeys: [KeyBinding]
    public static let `default` = NavFeature(
        enabled: true,
        activator: .default,
        exitKeys: [KeyBinding(mods: [], key: "escape"),
                   KeyBinding(mods: ["ctrl"], key: "c")])
}
extension NavFeature {
    enum CodingKeys: String, CodingKey { case enabled, activator, exitKeys }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NavFeature.default
        enabled = c.get(.enabled, default: d.enabled)
        activator = c.get(.activator, default: d.activator)
        exitKeys = c.get(.exitKeys, default: d.exitKeys)
    }
}

public struct MonitorsFeature: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var skipVirtualDisplayPattern: String
    public var optionTapCycle: Bool
    /// Modifier whose clean tap-and-release cycles displays: "alt" | "ctrl" | "cmd".
    public var cycleModifier: String
    public var optionScroll: Bool
    public var jumpKeys: [String]
    public var jumpClickKeys: [String]
    public var parkKeys: [String]
    public var parkPadding: Double
    public var focusLeft: KeyBinding
    public var focusRight: KeyBinding
    public var nextDisplay: KeyBinding
    public var prevDisplay: KeyBinding
    public static let `default` = MonitorsFeature(
        enabled: true, skipVirtualDisplayPattern: "16:9|HiDPI|Virtual",
        optionTapCycle: true, cycleModifier: "alt", optionScroll: true,
        jumpKeys: ["1", "2", "3"], jumpClickKeys: ["0", "9", "8"], parkKeys: ["4", "5", "6"],
        parkPadding: 30,
        focusLeft: KeyBinding(mods: ["cmd", "shift"], key: "-"),
        focusRight: KeyBinding(mods: ["cmd", "shift"], key: "="),
        nextDisplay: KeyBinding(mods: ["ctrl", "alt"], key: "right"),
        prevDisplay: KeyBinding(mods: ["ctrl", "alt"], key: "left"))
}
extension MonitorsFeature {
    enum CodingKeys: String, CodingKey {
        case enabled, skipVirtualDisplayPattern, optionTapCycle, cycleModifier, optionScroll
        case jumpKeys, jumpClickKeys, parkKeys, parkPadding, focusLeft, focusRight
        case nextDisplay, prevDisplay
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MonitorsFeature.default
        enabled = c.get(.enabled, default: d.enabled)
        skipVirtualDisplayPattern = c.get(.skipVirtualDisplayPattern, default: d.skipVirtualDisplayPattern)
        optionTapCycle = c.get(.optionTapCycle, default: d.optionTapCycle)
        cycleModifier = c.get(.cycleModifier, default: d.cycleModifier)
        optionScroll = c.get(.optionScroll, default: d.optionScroll)
        jumpKeys = c.get(.jumpKeys, default: d.jumpKeys)
        jumpClickKeys = c.get(.jumpClickKeys, default: d.jumpClickKeys)
        parkKeys = c.get(.parkKeys, default: d.parkKeys)
        parkPadding = c.get(.parkPadding, default: d.parkPadding)
        focusLeft = c.get(.focusLeft, default: d.focusLeft)
        focusRight = c.get(.focusRight, default: d.focusRight)
        nextDisplay = c.get(.nextDisplay, default: d.nextDisplay)
        prevDisplay = c.get(.prevDisplay, default: d.prevDisplay)
    }
}

public struct Features: Codable, Equatable, Sendable {
    public var nav: NavFeature
    public var monitors: MonitorsFeature
    public static let `default` = Features(nav: .default, monitors: .default)
}
extension Features {
    enum CodingKeys: String, CodingKey { case nav, monitors }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Features.default
        nav = c.get(.nav, default: d.nav)
        monitors = c.get(.monitors, default: d.monitors)
    }
}

public struct AppShortcut: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var key: String
    public var mods: [String]
    public var bundleID: String
    public var names: [String]
    public var clickTarget: String   // "center" | "bottom" | "none"
    public var exitNav: Bool

    public init(key: String = "", mods: [String] = [], bundleID: String = "",
                names: [String] = [], clickTarget: String = "center", exitNav: Bool = true) {
        self.id = UUID()
        self.key = key; self.mods = mods; self.bundleID = bundleID
        self.names = names; self.clickTarget = clickTarget; self.exitNav = exitNav
    }

    // `id` is UI-only identity; value equality ignores it so config comparison
    // and round-trip tests behave correctly.
    public static func == (l: AppShortcut, r: AppShortcut) -> Bool {
        l.key == r.key && l.mods == r.mods && l.bundleID == r.bundleID
            && l.names == r.names && l.clickTarget == r.clickTarget && l.exitNav == r.exitNav
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key); hasher.combine(mods); hasher.combine(bundleID)
        hasher.combine(names); hasher.combine(clickTarget); hasher.combine(exitNav)
    }
}
extension AppShortcut {
    // `id` is app-only, never serialized to the config file.
    enum CodingKeys: String, CodingKey { case key, mods, bundleID, names, clickTarget, exitNav }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        key = c.get(.key, default: "")
        mods = c.get(.mods, default: [])
        bundleID = c.get(.bundleID, default: "")
        names = c.get(.names, default: [])
        clickTarget = c.get(.clickTarget, default: "center")
        exitNav = c.get(.exitNav, default: true)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(mods, forKey: .mods)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(names, forKey: .names)
        try c.encode(clickTarget, forKey: .clickTarget)
        try c.encode(exitNav, forKey: .exitNav)
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var preset: String
    public var debug: Bool
    public var customLua: String
    public var tuning: Tuning
    public var features: Features
    public var apps: [AppShortcut]

    /// Ships with no launchers — the app detects installed apps and suggests them.
    public static let `default` = Config(
        preset: "default", debug: false, customLua: "", tuning: .default, features: .default,
        apps: [])
}
extension Config {
    enum CodingKeys: String, CodingKey { case preset, debug, customLua, tuning, features, apps }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        preset = c.get(.preset, default: d.preset)
        debug = c.get(.debug, default: d.debug)
        customLua = c.get(.customLua, default: d.customLua)
        tuning = c.get(.tuning, default: d.tuning)
        features = c.get(.features, default: d.features)
        apps = c.get(.apps, default: d.apps)
    }
}
