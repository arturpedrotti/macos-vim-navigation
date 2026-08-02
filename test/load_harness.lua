-- Load-time harness: mock the Hammerspoon API and execute the Spoon so every
-- module's setup() actually runs. Catches load/runtime errors.
-- The Spoon resolves its own path (debug.getinfo fallback) and dofile-loads
-- its files, so no package.path setup is needed here.
local SPOON = arg[1]

local counts = { globalBind = 0, modalBind = 0, eventtaps = 0, alerts = {},
                 hotkeyDeletes = 0, tapStops = 0 }

-- A permissive stub: any index returns a callable that returns another stub,
-- and it is itself callable. Concrete behaviors are layered on top where needed.
local stubmt
local function stub()
  return setmetatable({}, stubmt)
end
stubmt = {
  __index = function() return function() return stub() end end,
  __call = function() return stub() end,
}

local eventtap = {
  event = setmetatable({
    types = setmetatable({}, stubmt),
    properties = setmetatable({}, stubmt),
    newMouseEvent = function() return stub() end,
    newScrollEvent = function() return stub() end,
  }, stubmt),
  new = function()
    counts.eventtaps = counts.eventtaps + 1
    return { start = function(s) return s end,
             stop = function() counts.tapStops = counts.tapStops + 1 end }
  end,
  scrollWheel = function() end,
  leftClick = function() end,
  rightClick = function() end,
  keyStroke = function() end,
}

local function makeModal()
  return {
    bind = function(self, _, key)
      assert(type(key) == "string" and #key > 0, "modal:bind: invalid key " .. tostring(key))
      counts.modalBind = counts.modalBind + 1; return self
    end,
    enter = function() end,
    exit = function() end,
  }
end

hs = {
  configdir = SPOON,
  hotkey = {
    -- Mirror real Hammerspoon: an empty/nil key is an error. This is what catches
    -- accidental binds of cleared ("") config keys.
    bind = function(_, key)
      assert(type(key) == "string" and #key > 0, "hs.hotkey.bind: invalid key " .. tostring(key))
      counts.globalBind = counts.globalBind + 1
      return { delete = function() counts.hotkeyDeletes = counts.hotkeyDeletes + 1 end }
    end,
    modal = { new = makeModal },
  },
  mouse = {
    scrollDirection = function() return { natural = false } end,
    absolutePosition = function() return { x = 100, y = 100 } end,
    getCurrentScreen = function() return stub() end,
  },
  screen = setmetatable({
    allScreens = function() return {} end,
    mainScreen = function() return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end } end,
  }, stubmt),
  eventtap = eventtap,
  window = setmetatable({}, stubmt),
  application = setmetatable({}, stubmt),
  canvas = setmetatable({ new = function() return stub() end }, stubmt),
  timer = setmetatable({
    doAfter = function() return { stop = function() end } end,
    doEvery = function() return { stop = function() end } end,
    secondsSinceEpoch = function() return 0 end,
  }, stubmt),
  fnutils = { filter = function(t) return t end },
  keycodes = { map = setmetatable({}, { __index = function() return 0 end }) },
  pathwatcher = { new = function()
    return { start = function(s) return s end,
             stop = function() counts.tapStops = counts.tapStops + 1 end }
  end },
  urlevent = { bind = function() end },
  json = { read = function() return nil end }, -- overridden per scenario
  alert = setmetatable({ show = function(m) table.insert(counts.alerts, m) end }, { __call = function(_, m) table.insert(counts.alerts, m) end }),
}

-- Make config.lua's existence check (io.open on the config path) reflect whether
-- this scenario supplies a user config, and swallow the Spoon's status/error
-- file writes, while leaving all other file IO intact.
local realopen = io.open
local currentUserConfig = nil
io.open = function(path, mode)
  if type(path) == "string" and path:match("keydeck%-config%.json") then
    if currentUserConfig == nil then return nil end
    return { close = function() end }
  end
  if type(path) == "string" and (path:match("engine%-error%.txt") or path:match("engine%-status%.json")) then
    return { write = function() end, close = function() end }
  end
  return realopen(path, mode)
end

local function run(label, userConfig)
  currentUserConfig = userConfig
  counts.globalBind, counts.modalBind, counts.eventtaps, counts.alerts = 0, 0, 0, {}
  hs.json.read = function() return userConfig end

  -- dofile re-evaluates the Spoon fresh each scenario (no package.loaded cache).
  -- Use _start() (not start()) so errors propagate instead of being captured
  -- to the error file.
  local ok, err = pcall(function()
    local spoonObj = dofile(SPOON .. "/init.lua")
    spoonObj:init()
    return spoonObj:_start()
  end)
  if not ok then
    print(string.format("FAIL [%s]: %s", label, tostring(err)))
    return false
  end
  print(string.format("PASS [%s]  globalBinds=%d modalBinds=%d eventtaps=%d  alert=%q",
    label, counts.globalBind, counts.modalBind, counts.eventtaps, counts.alerts[#counts.alerts] or ""))
  return true
end

local allOk = true
-- Scenario 1: no user config (pure defaults).
allOk = run("defaults", nil) and allOk
-- Scenario 2: a STALE config still containing keys from removed features
-- (visual / cursor / windows, globalCursor* tuning) must load cleanly —
-- deep-merge keeps the unknown keys and nothing reads them.
allOk = run("stale-config-with-removed-keys", {
  preset = "old",
  tuning = { globalCursorStep = 180, dragMoveFrac = 0.05 },
  features = {
    visual = { enabled = true },
    cursor = { enabled = true, mods = { "alt", "cmd", "shift" }, keys = { left = "h", down = "j", up = "k", right = "l", click = "i" } },
    windows = { enabled = true, hide = { mods = { "alt", "cmd" }, key = "h" }, restore = { mods = { "alt", "shift" }, key = "r" } },
  },
}) and allOk
-- Scenario 3: no app launchers configured.
allOk = run("no-apps", { preset = "no-apps", apps = {} }) and allOk
-- Scenarios 4-6: every activator kind loads without error.
allOk = run("activator:double-tap", { features = { nav = { activator = { kind = "doubleTapModifier", modifier = "alt" } } } }) and allOk
allOk = run("activator:capslock", { features = { nav = { activator = { kind = "capsLock" } } } }) and allOk
allOk = run("activator:hyper", { features = { nav = { activator = { kind = "hyper", hotkey = { mods = { "ctrl", "alt", "shift", "cmd" }, key = "space" } } } } }) and allOk
-- Regression: cleared ("") keys must be SKIPPED, not bound (real hs errors on "").
allOk = run("empty-keys", {
  features = { monitors = {
    focusLeft = { mods = {}, key = "" }, focusRight = { mods = {}, key = "" },
    nextDisplay = { mods = {}, key = "" }, prevDisplay = { mods = {}, key = "" },
    jumpKeys = { "1", "", "3" }, jumpClickKeys = { "" }, parkKeys = { "" },
  } },
  apps = { { key = "", bundleID = "com.x.y", names = { "X" } }, { key = "c", bundleID = "com.openai.chat", names = { "ChatGPT" } } },
}) and allOk

-- Lifecycle: start() → stop() → start() must run cleanly, and stop() must
-- actually delete every tracked hotkey and stop every tap/watcher.
do
  currentUserConfig = nil
  hs.json.read = function() return nil end
  counts.globalBind, counts.modalBind, counts.eventtaps, counts.alerts = 0, 0, 0, {}
  counts.hotkeyDeletes, counts.tapStops = 0, 0
  local ok, err = pcall(function()
    local spoonObj = dofile(SPOON .. "/init.lua")
    spoonObj:init()
    spoonObj:_start()
    -- bindHotkeys() hotkeys must be tracked and deleted by stop() too.
    spoonObj:bindHotkeys({ toggle = { { "ctrl" }, "=" } })
    local boundBefore = counts.globalBind
    spoonObj:stop()
    assert(counts.hotkeyDeletes == boundBefore,
      ("stop() deleted %d of %d hotkeys"):format(counts.hotkeyDeletes, boundBefore))
    assert(counts.tapStops > 0, "stop() stopped no taps/watchers")
    assert(spoonObj.engine == nil, "stop() must clear self.engine")
    spoonObj:_start()
    -- The second start() must restore the bindHotkeys() toggle stop() deleted:
    -- the Spoon re-applies its remembered mapping, so the spoon-level hotkey
    -- is live (tracked) again and the bind count covers engine binds + toggle.
    assert(spoonObj._spoonHotkeys and #spoonObj._spoonHotkeys == 1,
      "second start() did not re-bind the bindHotkeys() toggle hotkey")
    assert(counts.globalBind == boundBefore * 2,
      ("second start() bound %d hotkeys, expected %d (engine + restored toggle)")
        :format(counts.globalBind - boundBefore, boundBefore))
  end)
  if ok then
    print(string.format("PASS [start-stop-start]  hotkeyDeletes=%d tapStops=%d", counts.hotkeyDeletes, counts.tapStops))
  else
    print("FAIL [start-stop-start]: " .. tostring(err))
    allOk = false
  end
end

os.exit(allOk and 0 or 1)
