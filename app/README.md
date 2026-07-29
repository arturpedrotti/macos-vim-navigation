# KeyDeck app

The whole product: a menu-bar app that **contains** the engine. Built as a
SwiftPM package — no Xcode project, no third-party dependencies.

```
app/
  Package.swift
  Sources/
    KeyDeckCore/     pure logic: Config model, ConfigStore, Validation, Entitlements, KeyNames
    KeyDeckEngine/   the runtime: Engine (CGEventTap), NavMode, Pointer, Displays,
                     Launcher, HUD, Repeater, Permissions, KeyCodes
    KeyDeck/         SwiftUI: App (menu bar + window), MainView, AppModel,
                     LauncherList, AddAppSheet, ShortcutRecorder, LoginItem, License
  Tests/KeyDeckCoreTests/   round-trip, old-config decode, conflicts, trial math
  test/run.sh              build + all assertions without XCTest
```

## The three layers

**`KeyDeckCore`** is the config contract. It decodes **tolerantly** — a partial
or 1.x config fills the rest from defaults — and `Validation` knows which keys
Nav Mode reserves, so a launcher can never be saved onto a binding that would
silently shadow it. No AppKit, so all of it is testable anywhere.

**`KeyDeckEngine`** is the runtime. `Engine` owns a single `CGEventTap`:

- Nav Mode **off** — a pure observer. Every event passes through untouched
  except the configured trigger (a hotkey, or a clean tap-and-release of a
  modifier, which costs the user no shortcut at all).
- Nav Mode **on** — every key is consumed and resolved by `NavMode.action`,
  which is pure and unit-tested. Unmapped keys are swallowed on purpose: in a
  modal layer, a stray key must never leak a character into the document
  underneath.

`HUD` renders the mode indicator and the `?` cheat sheet in non-activating
panels that ignore the mouse, so showing them never moves keyboard focus.

**`KeyDeck`** is the UI. `AppModel` holds the config; mutating it applies to the
running engine immediately and persists on a 500 ms debounce. There is no Apply
button, no reload and no heartbeat to verify — the engine is in this process.

## Build & run

```bash
cd app
swift build           # compile
swift run KeyDeck     # launch via SwiftPM (dev)
test/run.sh           # full verification (build + assertions [+ swift test if Xcode])

./bundle.sh           # → app/KeyDeck.app (release, ad-hoc signed, menu-bar app)
open KeyDeck.app
```

**Note on tests:** `Tests/KeyDeckCoreTests` uses XCTest, which ships with **full
Xcode** — `swift test` won't run under Command Line Tools alone. `test/run.sh`
therefore also compiles Core + Engine + `test/checks/main.swift` as one module
and runs the same assertions, so the logic is verified in either environment.

**Note on permissions:** Accessibility is remembered per *code identity*. An
ad-hoc signature changes on every rebuild, so during development macOS may ask
again after `./bundle.sh`. A Developer ID signature makes the grant stick.

## First run

No wizard. The window shows one button until Accessibility is granted; the app
polls for the answer and switches itself on the moment the box is ticked. With
no launchers configured, the list doubles as onboarding: suggestions drawn from
the apps actually installed on this Mac, one click to keep them. "Open at login"
is enabled automatically the first time — a keyboard layer that disappears on
reboot is worse than useless.

## Licensing (Gumroad)

14-day trial with everything unlocked, then **free forever with up to 3 app
launchers**; a Pro license removes the cap. Nothing ever stops working — the cap
only blocks *adding* launchers. Verification uses the Gumroad License API +
machine binding + a cached receipt (works offline after activation; silent
weekly re-verification does **not** consume activations).

**To enable for your product** — set the constants in
`Sources/KeyDeck/License.swift` → `LicenseConfig` (marked `TODO(release)`):

```swift
static let productID = "your_gumroad_product_id"   // Product → Advanced → product_id
static let buyURL    = URL(string: "https://gumroad.com/l/your-permalink")!
static let maxActivations = 3                       // per-key machine cap
```

Until `productID` is set, activation returns a clear "not configured" message and
the trial logic still works.
