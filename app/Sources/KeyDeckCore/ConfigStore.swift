import Foundation

/// Reads and writes the KeyDeck configuration.
///
/// The config lives in the app's own support directory. Versions up to 1.0 kept
/// it next to the Hammerspoon setup that used to run the engine; that file is
/// still read once, on first launch, so upgrading users keep their launchers.
public enum ConfigStore {
    public static var directory: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/KeyDeck")
    }

    public static var path: String {
        (directory as NSString).appendingPathComponent("config.json")
    }

    /// Where KeyDeck 1.x (the Hammerspoon Spoon) kept the same JSON.
    public static var legacyPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".hammerspoon/keydeck-config.json")
    }

    public static var fileExists: Bool { FileManager.default.fileExists(atPath: path) }

    /// Load the config, falling back to the 1.x location and then to defaults.
    /// The formats are identical, so a migrated file needs no conversion.
    public static func load() -> Config {
        if let data = FileManager.default.contents(atPath: path),
           let config = try? decoder().decode(Config.self, from: data) {
            return config
        }
        if let data = FileManager.default.contents(atPath: legacyPath),
           let migrated = try? decoder().decode(Config.self, from: data) {
            try? save(migrated)   // adopt it so the old file stops being consulted
            return migrated
        }
        return .default
    }

    /// Decode a Config from raw JSON data (used by tests and previews).
    public static func decode(_ data: Data) throws -> Config {
        try decoder().decode(Config.self, from: data)
    }

    /// Serialize a Config to pretty, stable JSON.
    public static func encode(_ config: Config) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(config)
    }

    /// Write the config to disk (creating Application Support/KeyDeck if needed).
    public static func save(_ config: Config) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try encode(config).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func decoder() -> JSONDecoder { JSONDecoder() }
}

public extension Config {
    /// A copy limited to what the app's UI manages: the nav shortcut, the
    /// display-cycle toggle + modifier, and the launcher list. Every monitor
    /// sub-binding the UI doesn't surface is cleared, so the running engine
    /// never has "phantom" shortcuts the user can't see or control.
    func curated() -> Config {
        var c = self
        c.features.monitors.optionScroll = false
        c.features.monitors.jumpKeys = []
        c.features.monitors.jumpClickKeys = []
        c.features.monitors.parkKeys = []
        c.features.monitors.focusLeft = KeyBinding()
        c.features.monitors.focusRight = KeyBinding()
        c.features.monitors.nextDisplay = KeyBinding()
        c.features.monitors.prevDisplay = KeyBinding()
        return c
    }

    /// Name of the app launcher already using this key+mods (for conflict prompts), or nil.
    func appLauncherName(forKey key: String, mods: [String], excludingID id: UUID?) -> String? {
        for a in apps where a.id != id {
            if a.key.lowercased() == key.lowercased() && Set(a.mods) == Set(mods) {
                return a.names.first ?? a.bundleID
            }
        }
        return nil
    }
}
