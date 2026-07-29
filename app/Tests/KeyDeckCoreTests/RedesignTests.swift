import XCTest
@testable import KeyDeckCore
import KeyDeckEngine

/// Tests for the single-window redesign: nav activator, the curated save,
/// display-cycle modifier, trial entitlements, and KeyNames. (The XCTest-free
/// runner in test/checks/main.swift mirrors these so they also run under
/// Command Line Tools.)
final class RedesignTests: XCTestCase {

    func testDefaultActivatorIsCtrlEquals() {
        let a = Config.default.features.nav.activator
        XCTAssertEqual(a.kind, "hotkey")
        XCTAssertEqual(a.hotkey, KeyBinding(mods: ["ctrl"], key: "="))
    }

    func testActivatorPartialDecode() throws {
        let json = #"{ "features": { "nav": { "activator": { "kind": "doubleTapModifier" } } } }"#
        let c = try ConfigStore.decode(Data(json.utf8))
        XCTAssertEqual(c.features.nav.activator.kind, "doubleTapModifier")
        XCTAssertEqual(c.features.nav.activator.hotkey.key, "=")          // default filled
    }

    func testKeyNames() {
        XCTAssertEqual(KeyNames.keyName(forKeyCode: 123), "left")
        XCTAssertEqual(KeyNames.keyName(forKeyCode: 49), "space")
        XCTAssertEqual(KeyNames.keyName(forKeyCode: 8), "c")
        XCTAssertEqual(KeyNames.keyName(forKeyCode: 79), "f18")
        XCTAssertEqual(KeyNames.keyName(forKeyCode: 9999, characters: "X"), "x")
        XCTAssertEqual(KeyNames.modifierNames(rawFlags: (1 << 20) | (1 << 19)), ["alt", "cmd"])
        XCTAssertTrue(KeyNames.isModifierKeyCode(54))
        XCTAssertFalse(KeyNames.isModifierKeyCode(8))
    }

    func testCuratedClearsUnsurfacedBindings() {
        let cur = Config.default.curated()
        XCTAssertTrue(cur.features.monitors.jumpKeys.isEmpty)
        XCTAssertTrue(cur.features.monitors.jumpClickKeys.isEmpty)
        XCTAssertTrue(cur.features.monitors.parkKeys.isEmpty)
        XCTAssertTrue(cur.features.monitors.focusLeft.key.isEmpty)
        XCTAssertTrue(cur.features.monitors.nextDisplay.key.isEmpty)
        XCTAssertFalse(cur.features.monitors.optionScroll)
        XCTAssertTrue(cur.features.monitors.optionTapCycle)               // surfaced — preserved
        XCTAssertEqual(cur.features.monitors.cycleModifier, "alt")        // surfaced — preserved
    }

    func testMiscDefaults() {
        XCTAssertTrue(Config.default.features.monitors.optionTapCycle)
        XCTAssertEqual(Config.default.features.monitors.cycleModifier, "alt")
        XCTAssertTrue(Config.default.apps.isEmpty)
        XCTAssertFalse(Config.default.debug)
        XCTAssertTrue(Config.default.customLua.isEmpty)
    }

    func testSuggestedLaunchers() {
        let installed = [("com.openai.chat", "ChatGPT"), ("company.thebrowser.Browser", "Arc"), ("com.apple.Terminal", "Terminal")]
        let s = SuggestedLaunchers.suggestions(installed: installed)
        XCTAssertTrue(s.contains { $0.key == "c" && $0.bundleID == "com.openai.chat" })
        XCTAssertTrue(s.contains { $0.key == "o" && $0.bundleID == "company.thebrowser.Browser" })
        XCTAssertTrue(s.contains { $0.key == "x" })   // Terminal
        let keys = SuggestedLaunchers.catalog.map { $0.key }
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(s.allSatisfy { !Validation.isReservedNavKey(key: $0.key, mods: $0.mods) },
                      "suggested keys must not collide with Nav Mode's own keys")
    }

    func testConflictHelper() {
        var c = Config.default
        c.apps = [AppShortcut(key: "c", bundleID: "com.openai.chat", names: ["ChatGPT"])]
        XCTAssertNotNil(c.appLauncherName(forKey: "c", mods: [], excludingID: nil))
        XCTAssertNil(c.appLauncherName(forKey: "z", mods: [], excludingID: nil))
    }

    func testTrialTierMath() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }
        XCTAssertEqual(Entitlements.tier(isLicensed: true, firstLaunch: daysAgo(100), now: now), .pro)
        XCTAssertEqual(Entitlements.tier(isLicensed: false, firstLaunch: now, now: now), .trial(daysLeft: 14))
        XCTAssertEqual(Entitlements.tier(isLicensed: false, firstLaunch: daysAgo(13.5), now: now), .trial(daysLeft: 1))
        XCTAssertEqual(Entitlements.tier(isLicensed: false, firstLaunch: daysAgo(14.5), now: now), .free)
        XCTAssertEqual(Entitlements.tier(isLicensed: false, firstLaunch: nil, now: now), .trial(daysLeft: 14))
    }

    func testLauncherCap() {
        XCTAssertTrue(Entitlements.canAddLauncher(currentCount: 99, tier: .trial(daysLeft: 3)))
        XCTAssertTrue(Entitlements.canAddLauncher(currentCount: 999, tier: .pro))
        XCTAssertFalse(Entitlements.canAddLauncher(currentCount: 3, tier: .free))
        XCTAssertTrue(Entitlements.canAddLauncher(currentCount: 2, tier: .free))
    }

    func testOldLicenseFileDecodes() throws {
        // license.json written before trials existed has no firstLaunchAt.
        let json = #"{ "licenseKey": "K", "verifiedAt": "2025-01-01T00:00:00Z" }"#
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let s = try d.decode(LicenseState.self, from: Data(json.utf8))
        XCTAssertNil(s.firstLaunchAt)
        XCTAssertTrue(s.isPro)
    }


    func testPersistenceRoundTrip() throws {
        var c = Config.default
        c.apps = [AppShortcut(key: "x", mods: [], bundleID: "com.x.y", names: ["X"])]
        c.features.nav.activator = NavActivator(kind: "hotkey", hotkey: KeyBinding(mods: ["ctrl", "alt"], key: "n"))
        c.features.monitors.cycleModifier = "ctrl"
        let restored = try ConfigStore.decode(try ConfigStore.encode(c))
        XCTAssertEqual(restored, c)
        XCTAssertEqual(restored.apps.first?.key, "x")
        XCTAssertEqual(restored.features.monitors.cycleModifier, "ctrl")
    }
}
