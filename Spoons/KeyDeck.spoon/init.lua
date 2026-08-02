--- === KeyDeck ===
---
--- Keyboard-centric navigation for macOS: a vim-inspired Navigation Mode
--- (pointer movement, scrolling, clicks), display switching on modifier
--- release, and app launchers — configured by the KeyDeck app or by editing
--- ~/.hammerspoon/keydeck-config.json.
---
--- Usage in ~/.hammerspoon/init.lua:
---   hs.loadSpoon("KeyDeck")
---   spoon.KeyDeck:start()
---
--- Download: https://github.com/arturgrochau/macos-vim-navigation
local obj = {}
obj.__index = obj

-- Metadata
obj.name = "KeyDeck"
obj.version = "1.0.0"
obj.author = "Artur Grochau <github.com/arturgrochau>"
obj.homepage = "https://github.com/arturgrochau/macos-vim-navigation"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Resolve this Spoon's own directory. Prefer Hammerspoon's API; fall back to
-- the script source path (also what lets the offline test harness load us).
obj.spoonPath = (function()
  if hs and hs.spoons and hs.spoons.scriptPath then
    local ok, p = pcall(hs.spoons.scriptPath)
    if ok and type(p) == "string" and #p > 0 then return p end
  end
  return debug.getinfo(1, "S").source:sub(2):match("(.*/)")
end)()

-- Load a file from inside the Spoon. dofile (not require) so nothing is
-- registered under generic names like "config" in package.loaded, which could
-- collide with a coexisting user's own modules.
local function loadModule(rel)
  return dofile(obj.spoonPath .. rel)
end

local supportDir = os.getenv("HOME") .. "/Library/Application Support/KeyDeck"

-- Write a heartbeat the GUI polls to confirm a reload actually happened.
local function writeStatus(cfg)
  pcall(function()
    hs.fs.mkdir(supportDir)
    local status = {
      loadedAt = os.time(),
      preset = cfg.preset or "default",
      navEnabled = (cfg.features and cfg.features.nav and cfg.features.nav.enabled) and true or false,
    }
    local f = io.open(supportDir .. "/engine-status.json", "w")
    if f then f:write(hs.json.encode(status)); f:close() end
  end)
end

-- Record (or clear) the last start error for the GUI to surface.
local function writeError(message)
  pcall(function()
    local f = io.open(supportDir .. "/engine-error.txt", "w")
    if f then f:write(message or ""); f:close() end
  end)
end

--- KeyDeck:init()
--- Method
--- Called automatically by hs.loadSpoon. Nothing to set up until start().
function obj:init()
  return self
end

function obj:_start()
  local defaults = loadModule("defaults.lua")
  local config   = loadModule("config.lua")
  local Core     = loadModule("lib/core.lua")
  local Overlay  = loadModule("lib/overlay.lua")

  local cfg = config.load(defaults)

  -- Mutual-exclusion guard: if the NAV activator taps the same modifier the
  -- display cycle listens on, a clean tap would both toggle NAV MODE and (after
  -- the idle window) switch displays. Disable the cycle for this session.
  do
    local nav, mon = cfg.features.nav, cfg.features.monitors
    local act = nav and nav.activator
    if nav and nav.enabled and mon and mon.enabled and mon.optionTapCycle
       and act and (act.kind == "tapModifier" or act.kind == "doubleTapModifier") then
      local base = tostring(act.modifier or ""):gsub("^left", ""):gsub("^right", ""):lower()
      if base == (mon.cycleModifier or "alt") then
        mon.optionTapCycle = false
        if cfg.debug then
          hs.alert.show("KeyDeck: display cycle disabled — NAV trigger uses the same modifier")
        end
      end
    end
  end

  local modal = hs.hotkey.modal.new()
  local ctx = Core.new(hs, modal, cfg)
  ctx.overlay = Overlay.new(ctx)

  -- Load enabled modules. Order: nav first (owns the modal lifecycle), then the rest.
  local function enabled(name) return cfg.features[name] and cfg.features[name].enabled end

  if enabled("nav") then loadModule("modules/nav.lua").setup(ctx) end
  loadModule("modules/apps.lua").setup(ctx) -- no-ops when cfg.apps is empty
  if enabled("monitors") then loadModule("modules/monitors.lua").setup(ctx) end

  -- Optional power-user escape hatch: raw Lua appended to the engine.
  if type(cfg.customLua) == "string" and #cfg.customLua > 0 then
    local fn, err = load(cfg.customLua, "keydeck-customLua")
    if fn then pcall(fn) elseif cfg.debug then hs.alert.show("customLua error: " .. tostring(err)) end
  end

  -- Debug-only reload binding. A Spoon coexisting with the user's own config
  -- must not claim ⌥R unconditionally; the pathwatcher and hammerspoon://reload
  -- cover normal reloads.
  if cfg.debug then
    ctx.bindGlobal({ "alt" }, "r", function()
      hs.reload()
      hs.alert("Reloaded")
    end)
  end

  -- Auto-reload when keydeck-config.json changes (GUI Apply takes effect with no CLI dep).
  ctx.configWatcher = hs.pathwatcher.new(hs.configdir, function(paths)
    for _, p in ipairs(paths) do
      if p:sub(-#"keydeck-config.json") == "keydeck-config.json" then
        hs.reload()
        return
      end
    end
  end):start()

  -- Manual reload via `open -g hammerspoon://reload` (GUI fallback).
  hs.urlevent.bind("reload", function() hs.reload() end)

  writeStatus(cfg)
  if cfg.debug then hs.alert.show("KeyDeck loaded — preset: " .. (cfg.preset or "default")) end
  self.engine = ctx
  -- stop() deletes the bindHotkeys() hotkeys; re-apply the remembered mapping
  -- so a stop() → start() cycle restores them. bindHotkeys() replaces any
  -- previous bindings, so this is safe to call unconditionally.
  if self._hotkeyMapping then self:bindHotkeys(self._hotkeyMapping) end
  return ctx
end

--- KeyDeck:start()
--- Method
--- Loads the config and activates every enabled module. Never crashes the
--- user's Hammerspoon config: a start error is captured to a file the KeyDeck
--- app reads and surfaces.
function obj:start()
  local ok, res = pcall(function() return self:_start() end)
  if ok then
    writeError("") -- clear any stale error
  else
    writeError(tostring(res))
    if hs and hs.alert then hs.alert.show("KeyDeck failed to start (open the KeyDeck app for details)") end
  end
  return self
end

--- KeyDeck:stop()
--- Method
--- Tears down everything start() created: exits NAV MODE, deletes every global
--- hotkey, and stops all event taps, watchers, timers, and overlays.
function obj:stop()
  -- Hotkeys bound via bindHotkeys() live on the Spoon object, not the engine,
  -- so delete them even if start() was never called.
  for _, hk in ipairs(self._spoonHotkeys or {}) do
    pcall(function() hk:delete() end)
  end
  self._spoonHotkeys = nil

  local ctx = self.engine
  if not ctx then return self end

  if ctx.navActive and ctx.modal then pcall(function() ctx.modal:exit() end) end

  for _, hk in ipairs(ctx.hotkeys or {}) do
    pcall(function() hk:delete() end)
  end

  -- Event taps and watchers are stored under known names on ctx.
  for _, name in ipairs({ "gResetTap", "navActivatorFlags", "navActivatorKeys",
                          "optionFlagsWatcher", "optionKeyWatcher", "configWatcher" }) do
    if ctx[name] then
      pcall(function() ctx[name]:stop() end)
      ctx[name] = nil
    end
  end

  -- The hammerspoon://reload handler _start() registered.
  pcall(function() hs.urlevent.bind("reload", nil) end)

  -- Hold-to-repeat timers.
  for key, t in pairs(ctx.held or {}) do
    pcall(function() t:stop() end)
    ctx.held[key] = nil
  end
  for key, h in pairs(ctx.holdTimers or {}) do
    pcall(function()
      if h.delayTimer then h.delayTimer:stop() end
      if h.repeatTimer then h.repeatTimer:stop() end
    end)
    ctx.holdTimers[key] = nil
  end
  -- Overlay canvases.
  if ctx.overlay then
    pcall(function() ctx.overlay.hideHelp() end)
    if ctx.overlay.normal then
      pcall(function() ctx.overlay.normal:delete() end)
      ctx.overlay.normal = nil
    end
  end

  self.engine = nil
  return self
end

--- KeyDeck:bindHotkeys(mapping)
--- Method
--- Standard Spoon hotkey binding. Supported actions:
---  * toggle - toggle NAV MODE
---
--- Example:
---   spoon.KeyDeck:bindHotkeys({ toggle = { { "ctrl" }, "=" } })
function obj:bindHotkeys(mapping)
  -- Remember the mapping so _start() can re-apply it after a stop() deleted
  -- the hotkey objects (stop() intentionally leaves this field alone).
  self._hotkeyMapping = mapping
  local spec = {
    toggle = function()
      if self.engine and self.engine.toggleNav then self.engine.toggleNav() end
    end,
  }
  -- Bound directly (not via hs.spoons.bindHotkeysToSpec, which keeps the hotkey
  -- objects to itself) so stop() can track and delete them. Rebinding replaces
  -- the previous set, matching bindHotkeysToSpec's behavior.
  for _, hk in ipairs(self._spoonHotkeys or {}) do
    pcall(function() hk:delete() end)
  end
  self._spoonHotkeys = {}
  for name, key in pairs(mapping or {}) do
    if spec[name] and type(key) == "table" then
      local hk
      if hs.hotkey.bindSpec then
        hk = hs.hotkey.bindSpec(key, spec[name])
      else
        hk = hs.hotkey.bind(key[1] or {}, key[2], spec[name])
      end
      if hk then table.insert(self._spoonHotkeys, hk) end
    end
  end
  return self
end

return obj
