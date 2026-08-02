import XCTest
@testable import KeyDeckCore

final class ConfigTests: XCTestCase {

    func testDefaultRoundTrips() throws {
        let data = try ConfigStore.encode(.default)
        let decoded = try ConfigStore.decode(data)
        XCTAssertEqual(decoded, .default)
    }

    func testPartialConfigFillsDefaults() throws {
        // Only flips one nested value; everything else must fall back to defaults.
        let json = #"{ "features": { "monitors": { "cycleModifier": "ctrl" } } }"#
        let c = try ConfigStore.decode(Data(json.utf8))
        XCTAssertEqual(c.features.monitors.cycleModifier, "ctrl")  // override applied
        XCTAssertEqual(c.tuning.scrollStep, 62)                    // default filled
        XCTAssertTrue(c.features.nav.enabled)                      // default filled
        XCTAssertTrue(c.features.monitors.optionTapCycle)          // default filled
    }

    func testOldConfigWithRemovedBlocksDecodes() throws {
        // Configs written before visual/cursor/windows were removed must load.
        let json = #"""
        { "features": { "visual": { "enabled": true },
                        "cursor": { "enabled": true, "keys": { "left": "h" } },
                        "windows": { "enabled": true } },
          "tuning": { "globalCursorStep": 180, "dragMoveFrac": 0.05, "scrollStep": 70 },
          "apps": [ { "key": "c", "bundleID": "com.openai.chat", "names": ["ChatGPT"] } ] }
        """#
        let c = try ConfigStore.decode(Data(json.utf8))
        XCTAssertEqual(c.tuning.scrollStep, 70)
        XCTAssertEqual(c.apps.count, 1)
    }

    func testKeyBindingPartialDecode() throws {
        let b = try JSONDecoder().decode(KeyBinding.self, from: Data(#"{ "key": "x" }"#.utf8))
        XCTAssertEqual(b.key, "x")
        XCTAssertEqual(b.mods, [])
    }

    func testDefaultHasNoConflicts() {
        XCTAssertTrue(Validation.conflicts(in: .default).isEmpty,
                      "default config should not self-conflict")
    }

    func testDuplicateLauncherKeyDetected() {
        var c = Config.default
        c.apps = [AppShortcut(key: "c", bundleID: "a"), AppShortcut(key: "c", bundleID: "b")]
        XCTAssertTrue(Validation.conflicts(in: c).contains { $0.scope == "NAV MODE" && $0.signature == "C" })
    }

    func testLauncherOnReservedNavKeyDetected() {
        var c = Config.default
        c.apps = [AppShortcut(key: "j", bundleID: "a")]
        XCTAssertTrue(Validation.conflicts(in: c).contains { $0.scope == "NAV MODE" && $0.signature == "J" })
        XCTAssertTrue(Validation.isReservedNavKey(key: "j", mods: []))
        XCTAssertTrue(Validation.isReservedNavKey(key: "m", mods: ["shift"]))
        XCTAssertFalse(Validation.isReservedNavKey(key: "z", mods: []))
    }

    func testLauncherOnExitKeyDetected() {
        // Exit keys and launchers share the NAV MODE namespace, so a launcher
        // placed on an exit key (default: ⌃C) must be reported as a conflict.
        var c = Config.default
        c.apps = [AppShortcut(key: "c", mods: ["ctrl"], bundleID: "a")]
        XCTAssertTrue(Validation.conflicts(in: c).contains { $0.scope == "NAV MODE" && $0.signature == "⌃C" })
    }

    func testEncodedJSONOmitsAppID() throws {
        var c = Config.default
        c.apps = [AppShortcut(key: "c", bundleID: "com.openai.chat", names: ["ChatGPT"])]
        let str = String(decoding: try ConfigStore.encode(c), as: UTF8.self)
        XCTAssertFalse(str.contains("\"id\""), "app id must not be serialized")
        XCTAssertTrue(str.contains("com.openai.chat"))
    }

    func testDisplayFormatting() {
        XCTAssertEqual(Validation.display(mods: ["alt", "cmd", "shift"], key: "h"), "⌥⇧⌘H")
        XCTAssertEqual(Validation.display(mods: [], key: "c"), "C")
    }
}
