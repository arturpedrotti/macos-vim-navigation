# KeyDeck.spoon — legacy (1.x)

> **This is not the product any more.** KeyDeck 2.0 is a self-contained macOS app
> with its own native engine: no Hammerspoon, no Lua, no install step beyond
> granting Accessibility. See the [main README](../../README.md).
>
> This Spoon is kept for people who already run Hammerspoon and would rather
> drive KeyDeck from their existing config. It reads
> `~/.hammerspoon/keydeck-config.json`, which the 2.0 app no longer writes — so
> if you run both, configure this one by hand.

The 1.x KeyDeck engine, packaged as a standard [Hammerspoon Spoon](https://www.hammerspoon.org/Spoons/).
It coexists with any existing Hammerspoon configuration.

## Usage

Copy this directory to `~/.hammerspoon/Spoons/KeyDeck.spoon`, then in your `init.lua`:

```lua
hs.loadSpoon("KeyDeck")
spoon.KeyDeck:start()
```

API (standard Spoon lifecycle):

| Method | What it does |
|---|---|
| `:start()` | Load the config and activate every enabled module. Errors never crash your config — they're captured to a file the KeyDeck app surfaces. |
| `:stop()` | Tear down everything: exits Nav Mode, deletes all hotkeys, stops all event taps, watchers, timers, and overlays. |
| `:bindHotkeys({ toggle = { mods, key } })` | Bind the Nav Mode toggle. Bound via `hs.hotkey.bindSpec` and tracked by the Spoon, so `:stop()` deletes them; calling it again replaces the previous bindings. |

## Configuration

Behavior is driven by `~/.hammerspoon/keydeck-config.json`, deep-merged over
`defaults.lua` — any subset of keys is valid, and the engine reloads automatically
when the file changes. You create and edit this file by hand — the 2.0 app no
longer writes it (its own config lives at
`~/Library/Application Support/KeyDeck/config.json`).
See `config/keydeck-config.example.json` and `config/config.schema.json` at the
repo root for the full contract.

```jsonc
{
  "features": {
    "nav": {                       // Nav Mode: hjkl move, d/u scroll, i/a click, ? help
      "enabled": true,
      "activator": { "kind": "hotkey", "hotkey": { "mods": ["ctrl"], "key": "=" } }
    },
    "monitors": {                  // tap cycleModifier alone -> next display
      "enabled": true,
      "optionTapCycle": true,
      "cycleModifier": "alt"       // "alt" | "ctrl" | "cmd"
    }
  },
  "apps": [                        // in Nav Mode, key -> exit + launch/focus app
    { "key": "s", "bundleID": "com.apple.Safari", "names": ["Safari"] }
  ]
}
```

## Layout

```
KeyDeck.spoon/
  init.lua            Spoon object: metadata, :start/:stop/:bindHotkeys
  config.lua          read keydeck-config.json, deep-merge over defaults
  defaults.lua        canonical default config
  lib/
    core.lua          shared ctx: hotkey tracking, mouse/scroll/hold-to-repeat helpers
    overlay.lua       "-- NORMAL --" indicator + the ? help panel
  modules/
    nav.lua           Nav Mode: modal lifecycle, movement, scrolling, clicks
    apps.lua          app launchers (data-driven from cfg.apps)
    monitors.lua      display cycle on modifier release, jumps, window focus
```

For the GUI, install scripts, and tests, see the repository root.
