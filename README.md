# KeyDeck

**A vim-inspired navigation layer for macOS. One app, one permission, no dependencies.**

You have run out of keyboard shortcuts. Every sensible ⌘ and ⌥ combination is
taken by an app you actually use, and the ones left are three-finger
contortions you will never remember.

KeyDeck gives the whole keyboard back. Press one trigger and you are in **Nav
Mode**, where every bare key is yours again:

| | |
|---|---|
| `h j k l` | move the pointer (`⇧` for big jumps) |
| `d` `u` `w` `b` | scroll — down, up, left, right (`⇧` for a full page) |
| `gg` / `G` | top / bottom |
| `space` / `⇧space` / `i` / `a` | click / double-click / select line / right-click |
| `1 2 3` and `[` `]` | jump the pointer between displays |
| `⇧A` / `⇧I` | next / previous app |
| **your own letters** | launch or focus an app — `s` for Slack, `o` for your browser… |
| `?` | the full list, generated from your config |
| `esc` | leave |

Because Nav Mode is *modal*, none of this costs you a system shortcut. And the
trigger itself needn't cost one either — set it to a clean tap of right ⌥, and
⌥ keeps working normally in every combination you already use.

## Install

Download `KeyDeck.app`, drag it to Applications, open it, click **Turn on
KeyDeck**, tick it in the Accessibility list. That is the whole setup.

Accessibility is the *only* permission KeyDeck asks for — macOS requires it of
anything that reads the keyboard. There is no helper daemon, no scripting
runtime, and nothing to install alongside it.

To build from source:

```bash
cd app && ./bundle.sh    # → app/KeyDeck.app
open KeyDeck.app
```

Requires macOS 13+ and the macOS SDK (Command Line Tools or Xcode). No external
packages.

## How it works

KeyDeck is one Swift process. A `CGEventTap` watches the keyboard: while Nav
Mode is off it passes every event through untouched except your trigger; while
Nav Mode is on it consumes keys and turns them into pointer, scroll, click,
display and launcher actions. Settings mutate the running engine directly —
there is no apply step, no reload, and no way to be "saved but not running".

| Path | What it is |
|---|---|
| `app/Sources/KeyDeckEngine/` | The engine — event tap, Nav Mode, pointer/display/launcher actions, HUD |
| `app/Sources/KeyDeckCore/` | Config model, storage, validation, entitlements (pure, testable) |
| `app/Sources/KeyDeck/` | The SwiftUI menu-bar app ([details](app/README.md)) |
| `config/` | Config schema + example config |
| `Spoons/KeyDeck.spoon/` | **Legacy.** The 1.x [Hammerspoon](https://www.hammerspoon.org) engine, kept for people already running Hammerspoon |
| `app/test/run.sh` | Offline test suite |

## Configuration

Settings live at `~/Library/Application Support/KeyDeck/config.json` and are
managed by the app. A 1.x config at `~/.hammerspoon/keydeck-config.json` is
migrated automatically on first launch. Hand-editing works too — any subset of
keys is valid and the rest falls back to defaults. See
[`config/keydeck-config.example.json`](config/keydeck-config.example.json) and
[`config/config.schema.json`](config/config.schema.json).

## Upgrading from 1.x

Your launchers and trigger carry over automatically. The Hammerspoon Spoon is no
longer used by the app; to stop it running as well, remove the two KeyDeck lines
from `~/.hammerspoon/init.lua`.

## Pricing

Free 14-day trial with everything unlocked; afterwards KeyDeck stays free with
up to 3 app launchers. A Pro license (one-time, via Gumroad) removes the limit.
Nav Mode itself never stops working.

## Release checklist

- [ ] Set the real Gumroad product ID in `app/Sources/KeyDeck/License.swift`
      (`LicenseConfig.productID`) and verify `buyURL` — activation fails with
      "not configured" until then.
- [ ] `app/test/run.sh` green.
- [ ] Sign `KeyDeck.app` with a Developer ID certificate and notarize it.
      Accessibility permission is remembered per code identity, so an ad-hoc
      signature means macOS re-asks after every rebuild.
- [ ] Manual smoke test: fresh user → open app → grant permission → trigger
      enters Nav Mode → `?` lists your launchers → a launcher key opens its app.

## License

MIT — see [LICENSE](LICENSE). Built by [Artur Grochau](https://github.com/arturgrochau).
