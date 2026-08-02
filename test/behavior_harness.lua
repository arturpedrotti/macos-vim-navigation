-- Behavioral harness: load the engine against an instrumented mock hs, then
-- INVOKE the registered callbacks and assert their concrete effects. Unlike
-- load_harness.lua (which only checks that setup() runs), this exercises the
-- actual logic: movement math, scroll deltas, clicks, app launch, monitor jumps,
-- and the option-tap idle/conflict guard.
local SPOON = arg[1]

----------------------------------------------------------------------
-- Instrumented mock state
----------------------------------------------------------------------
local rec = { scrolls = {}, scrollPosts = {}, clicks = 0, rclicks = 0, downs = 0,
              keystrokes = {}, launches = {}, modalExits = 0, modalEnters = 0, alerts = {} }
local CLOCK = 100
local mousePos = { x = 0, y = 0 }

-- Three physical screens, left to right.
local function mkScreen(id, x, w, h)
  return {
    _id = id, _f = { x = x, y = 0, w = w, h = h },
    id = function(s) return s._id end,
    frame = function(s) return s._f end,
    name = function() return "Display " .. id end,
  }
end
local S = { mkScreen(1, 0, 1440, 900), mkScreen(2, 1440, 1920, 1080), mkScreen(3, 3360, 1280, 720) }
local function screenContaining(p)
  for _, s in ipairs(S) do
    local f = s._f
    if p.x >= f.x and p.x < f.x + f.w then return s end
  end
  return S[1]
end
local function centerOf(s) return { x = s._f.x + s._f.w / 2, y = s._f.y + s._f.h / 2 } end

-- Captured bindings + event-tap callbacks.
local modalBinds, globalBinds, keyDownCbs, flagsCbs = {}, {}, {}, {}
local function modKey(mods, key)
  local m = {}
  for _, x in ipairs(mods or {}) do m[#m + 1] = x end
  table.sort(m)
  return table.concat(m, "+") .. ":" .. key
end

-- Deferred-timer queue (doAfter is queued, not immediate; flush() runs it).
local timerQ = {}
local function flush()
  local n = 0
  while #timerQ > 0 and n < 1000 do
    local fn = table.remove(timerQ, 1)
    n = n + 1
    pcall(fn)
  end
end

local stubmt = { __index = function() return function() end end, __call = function() return nil end }

local modal = {
  bind = function(self, mods, key, press, release)
    modalBinds[modKey(mods, key)] = { press = press, release = release }
    return self
  end,
  -- Emulate Hammerspoon: enter/exit invoke the entered()/exited() hooks.
  enter = function(self) rec.modalEnters = rec.modalEnters + 1; if self.entered then self:entered() end end,
  exit = function(self) rec.modalExits = rec.modalExits + 1; if self.exited then self:exited() end end,
}

local function mkMouseEvent() -- result of newMouseEvent / newScrollEvent
  return {
    setProperty = function(s) return s end,
    post = function() rec.downs = rec.downs + 1 end,
  }
end

hs = {
  configdir = SPOON,
  hotkey = {
    bind = function(mods, key, press, release)
      globalBinds[modKey(mods, key)] = { press = press, release = release }
    end,
    modal = { new = function() return modal end },
  },
  mouse = {
    scrollDirection = function() return { natural = false } end,
    absolutePosition = function(p)
      if p then mousePos = { x = p.x, y = p.y } else return { x = mousePos.x, y = mousePos.y } end
    end,
    getCurrentScreen = function() return screenContaining(mousePos) end,
  },
  screen = {
    allScreens = function() return { S[1], S[2], S[3] } end,
    mainScreen = function() return screenContaining(mousePos) end,
  },
  eventtap = {
    event = setmetatable({
      types = { flagsChanged = "flagsChanged", keyDown = "keyDown" },
      properties = setmetatable({}, stubmt),
      newMouseEvent = function() return mkMouseEvent() end,
      newScrollEvent = function(delta) return { post = function() table.insert(rec.scrollPosts, delta) end } end,
    }, stubmt),
    new = function(types, fn)
      local t = types[1]
      if t == "flagsChanged" then table.insert(flagsCbs, fn)
      elseif t == "keyDown" then table.insert(keyDownCbs, fn) end
      return { start = function(s) return s end }
    end,
    scrollWheel = function(delta) table.insert(rec.scrolls, delta) end,
    leftClick = function() rec.clicks = rec.clicks + 1 end,
    rightClick = function() rec.rclicks = (rec.rclicks or 0) + 1 end,
    keyStroke = function(mods, key) table.insert(rec.keystrokes, key) end,
  },
  window = setmetatable({
    focusedWindow = function() return nil end,
    visibleWindows = function() return {} end,
    orderedWindows = function() return {} end,
    get = function() return nil end,
  }, stubmt),
  application = setmetatable({
    get = function() return nil end,
    launchOrFocusByBundleID = function(id) table.insert(rec.launches, id); return { mainWindow = function() return nil end } end,
    open = function(id) table.insert(rec.launches, id); return nil end,
    frontmostApplication = function() return nil end,
    runningApplications = function() return {} end,
  }, stubmt),
  canvas = setmetatable({ new = function() return setmetatable({}, { __index = function() return function(s) return s end end }) end }, stubmt),
  timer = {
    doAfter = function(_, fn) table.insert(timerQ, fn); return { stop = function() for i, f in ipairs(timerQ) do if f == fn then table.remove(timerQ, i) break end end end } end,
    doEvery = function() return { stop = function() end } end,
    secondsSinceEpoch = function() return CLOCK end,
  },
  fnutils = { filter = function(t) return t end },
  keycodes = { map = { d = 2, u = 32 } },
  pathwatcher = { new = function() return { start = function(s) return s end } end },
  urlevent = { bind = function() end },
  json = { read = function() return nil end },
  alert = setmetatable({ show = function(m) table.insert(rec.alerts, m) end }, { __call = function(_, m) table.insert(rec.alerts, m) end }),
}

----------------------------------------------------------------------
-- Load the Spoon with a user config exercising extra features
----------------------------------------------------------------------
-- Injected through the REAL config path: io.open says the config file exists,
-- hs.json.read returns this table, and config.lua deep-merges it over defaults.
-- The option-tap display cycle is on, and the nav activator is pinned to a
-- Right-⌘ tap so it doesn't overlap the Option-based cycle in these tests.
local userConfig = {
  features = {
    monitors = { optionTapCycle = true },
    nav = { activator = { kind = "tapModifier", modifier = "rightCmd", onRelease = true } },
  },
  -- Defaults ship no launchers; the launch test needs one.
  apps = {
    { key = "c", mods = {}, bundleID = "com.openai.chat", names = { "ChatGPT" }, clickTarget = "bottom", exitNav = true },
  },
}
hs.json.read = function() return userConfig end
local realopen = io.open
io.open = function(path, mode)
  if type(path) == "string" and path:match("keydeck%-config%.json") then
    return { close = function() end }
  end
  if type(path) == "string" and (path:match("engine%-error%.txt") or path:match("engine%-status%.json")) then
    return { write = function() end, close = function() end }
  end
  return realopen(path, mode)
end

local ok, err = pcall(function()
  local spoonObj = dofile(SPOON .. "/init.lua")
  spoonObj:init()
  return spoonObj:_start()
end)
if not ok then print("FAIL load: " .. tostring(err)); os.exit(1) end

----------------------------------------------------------------------
-- Assertion helpers
----------------------------------------------------------------------
local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print("  ok   " .. name)
  else fail = fail + 1; print("  FAIL " .. name .. (detail and ("  -> " .. detail) or "")) end
end
local function approx(a, b) return math.abs(a - b) < 0.5 end
local function resetRec() rec.scrolls, rec.scrollPosts, rec.clicks, rec.downs, rec.keystrokes, rec.launches, rec.modalExits, rec.modalEnters, rec.alerts = {}, {}, 0, 0, {}, {}, 0, 0, {} end
local function setMouse(p) mousePos = { x = p.x, y = p.y } end
local function pressModal(mods, key) local b = modalBinds[modKey(mods, key)]; assert(b, "no modal bind " .. modKey(mods, key)); b.press() end
local function pressGlobal(mods, key) local b = globalBinds[modKey(mods, key)]; assert(b, "no global bind " .. modKey(mods, key)); b.press() end

----------------------------------------------------------------------
-- Tests
----------------------------------------------------------------------
print("NAV movement (steps relative to screen under cursor):")
-- On S1 (w=1440,h=900): h/l move x by ±w/8=±180; j/k move y by ±h/8=±112.5
setMouse({ x = 720, y = 450 }); resetRec(); pressModal({}, "h")
check("h moves left by w/8", approx(mousePos.x, 720 - 180) and approx(mousePos.y, 450), ("x=%.1f"):format(mousePos.x))
setMouse({ x = 720, y = 450 }); pressModal({}, "l")
check("l moves right by w/8", approx(mousePos.x, 720 + 180))
setMouse({ x = 720, y = 450 }); pressModal({}, "j")
check("j moves down by h/8", approx(mousePos.y, 450 + 112.5))
setMouse({ x = 720, y = 450 }); pressModal({}, "k")
check("k moves up by h/8", approx(mousePos.y, 450 - 112.5))
setMouse({ x = 720, y = 450 }); pressModal({ "shift" }, "h")
check("Shift+h moves left by w/2", approx(mousePos.x, 720 - 720))

print("NAV scroll:")
resetRec(); pressModal({}, "d")
check("d scrolls down 62px", #rec.scrolls == 1 and rec.scrolls[1][2] == -62, ("got %d events"):format(#rec.scrolls))
resetRec(); pressModal({}, "u")
check("u scrolls up 62px", #rec.scrolls == 1 and rec.scrolls[1][2] == 62)
resetRec(); pressModal({ "shift" }, "u")
check("Shift+u scrolls 8x (496px)", #rec.scrolls == 1 and rec.scrolls[1][2] == 62 * 8)

print("gg / G (double-tap g scrolls to top):")
resetRec(); pressModal({}, "g")
check("first g posts nothing yet", #rec.scrollPosts == 0)
pressModal({}, "g")
check("gg posts scroll-to-top (large +y)", #rec.scrollPosts == 1 and rec.scrollPosts[1][2] > 100000)
resetRec(); pressModal({ "shift" }, "g")
check("G posts scroll-to-bottom (large -y)", #rec.scrollPosts == 1 and rec.scrollPosts[1][2] < -100000)

print("NAV clicks:")
resetRec(); pressModal({}, "i")
-- triple-click = 3 (down+up) pairs = 6 posted mouse events
check("i performs triple-click (3 down+up pairs)", rec.downs == 6, ("posts=%d"):format(rec.downs))
resetRec(); pressModal({}, "a")
check("a right-clicks", (rec.rclicks or 0) == 1)

print("App shortcut (c -> ChatGPT):")
resetRec(); timerQ = {}; pressModal({}, "c"); flush()
check("c launches ChatGPT bundle", rec.launches[1] == "com.openai.chat", table.concat(rec.launches, ","))
check("c exits NAV MODE", rec.modalExits == 1)

print("Monitors — jump to physical screen center:")
setMouse({ x = 0, y = 0 }); resetRec(); pressGlobal({ "alt" }, "2")
check("opt+2 centers on screen 2", approx(mousePos.x, centerOf(S[2]).x) and approx(mousePos.y, centerOf(S[2]).y),
  ("%.0f,%.0f"):format(mousePos.x, mousePos.y))
setMouse({ x = 0, y = 0 }); resetRec(); timerQ = {}; pressGlobal({ "alt" }, "9"); flush()
check("opt+9 centers on screen 2 AND clicks", approx(mousePos.x, centerOf(S[2]).x) and rec.clicks == 1, ("clicks=%d"):format(rec.clicks))
setMouse({ x = 0, y = 0 }); resetRec(); pressGlobal({ "alt" }, "4")
check("opt+4 parks bottom-right of screen 1", approx(mousePos.x, 1440 - 30) and approx(mousePos.y, 900 - 30))

print("Next / previous display (cursor cycles physical screens, wrap-around):")
setMouse(centerOf(S[1])); resetRec(); pressGlobal({ "ctrl", "alt" }, "right")
check("next display: S1 -> S2", approx(mousePos.x, centerOf(S[2]).x))
pressGlobal({ "ctrl", "alt" }, "right"); pressGlobal({ "ctrl", "alt" }, "right")
check("next display wraps S3 -> S1", approx(mousePos.x, centerOf(S[1]).x), ("x=%.0f"):format(mousePos.x))
setMouse(centerOf(S[1])); pressGlobal({ "ctrl", "alt" }, "left")
check("prev display wraps S1 -> S3", approx(mousePos.x, centerOf(S[3]).x), ("x=%.0f"):format(mousePos.x))

print("Option-tap screen cycle + conflict guard (the no-conflict feature):")
local flags = function(t, kc) for _, cb in ipairs(flagsCbs) do cb({ getFlags = function() return t end, getKeyCode = function() return kc or 0 end }) end end
local keydown = function(f, kc, ch) for _, cb in ipairs(keyDownCbs) do cb({
  getFlags = function() return f end, getKeyCode = function() return kc end, getCharacters = function() return ch end }) end end

-- (a) Clean tap: option down then up, idle, no other key -> cycle to next screen.
setMouse(centerOf(S[1])); resetRec(); timerQ = {}; CLOCK = 100
flags({ alt = true }); flags({}); flush()
check("clean ⌥ tap cycles S1 -> S2", approx(mousePos.x, centerOf(S[2]).x), ("x=%.0f"):format(mousePos.x))

-- (b) Conflict: a key pressed while option held -> NO cycle on release.
setMouse(centerOf(S[1])); resetRec(); timerQ = {}; CLOCK = 200
flags({ alt = true }); keydown({ alt = true, cmd = true }, 9, "j"); flags({}); flush()
check("⌥ tap with Cmd+J held does NOT cycle", approx(mousePos.x, centerOf(S[1]).x), ("x=%.0f"):format(mousePos.x))

-- (b2) Reverse order: a second MODIFIER pressed and released during the ⌥ hold
-- (⌥ down, ⇧ down, ⇧ up, ⌥ up) is a chord, not a clean tap -> NO cycle.
setMouse(centerOf(S[1])); resetRec(); timerQ = {}; CLOCK = 250
flags({ alt = true }); flags({ alt = true, shift = true }); flags({ alt = true }); flags({}); flush()
check("⌥ tap with a ⇧ chord mid-hold does NOT cycle", approx(mousePos.x, centerOf(S[1]).x), ("x=%.0f"):format(mousePos.x))

-- (c) Option+D scrolls (and counts as 'other key', also no cycle).
setMouse(centerOf(S[1])); resetRec(); timerQ = {}; CLOCK = 300
flags({ alt = true }); keydown({ alt = true }, hs.keycodes.map.d, "d")
check("⌥+D emits a scroll", #rec.scrolls == 1 and rec.scrolls[1][2] == -260, ("n=%d"):format(#rec.scrolls))
flags({}); flush()
check("⌥+D does not cycle screens", approx(mousePos.x, centerOf(S[1]).x))

-- (d) The idle guard covers ALL typing: a plain keypress (no modifier held)
-- immediately followed by a clean ⌥ tap must NOT cycle...
setMouse(centerOf(S[1])); resetRec(); timerQ = {}; CLOCK = 350
keydown({}, 8, "c")
flags({ alt = true }); flags({}); flush()
check("typing then an immediate ⌥ tap does NOT cycle", approx(mousePos.x, centerOf(S[1]).x), ("x=%.0f"):format(mousePos.x))
-- ...but once the keyboard has been idle past optionReleaseIdleSeconds (2.0),
-- the same tap cycles again.
CLOCK = 353
flags({ alt = true }); flags({}); flush()
check("⌥ tap after the idle window cycles", approx(mousePos.x, centerOf(S[2]).x), ("x=%.0f"):format(mousePos.x))

print("Right-⌘ nav activator (clean tap toggles NAV MODE; combo does not):")
-- Clean tap: right-cmd down (keycode 54, only cmd flag) then up, no other key.
resetRec()
flags({ cmd = true }, 54); flags({}, 54)
check("clean Right-⌘ tap enters NAV MODE", rec.modalEnters == 1, ("enters=%d"):format(rec.modalEnters))
-- Tap again toggles back out.
flags({ cmd = true }, 54); flags({}, 54)
check("second Right-⌘ tap exits NAV MODE", rec.modalExits == 1, ("exits=%d"):format(rec.modalExits))
-- Combo (Right-⌘ + C) must NOT toggle.
resetRec()
flags({ cmd = true }, 54); keydown({ cmd = true }, 8, "c"); flags({}, 54)
check("Right-⌘+C does not toggle", rec.modalEnters == 0 and rec.modalExits == 0,
  ("enters=%d exits=%d"):format(rec.modalEnters, rec.modalExits))
-- A second modifier chorded in and released mid-hold must not toggle either.
resetRec()
flags({ cmd = true }, 54); flags({ cmd = true, shift = true }, 56); flags({ cmd = true }, 56); flags({}, 54)
check("Right-⌘ tap with a ⇧ chord mid-hold does not toggle", rec.modalEnters == 0 and rec.modalExits == 0,
  ("enters=%d exits=%d"):format(rec.modalEnters, rec.modalExits))
check("help overlay '?' is bound", modalBinds[modKey({ "shift" }, "/")] ~= nil)

-- Reload the Spoon with a different user config. The flags/keyDown callback
-- lists are cleared first so the helpers address only the new instance.
local function reloadWith(cfg)
  flagsCbs, keyDownCbs = {}, {}
  userConfig = cfg
  return pcall(function()
    local spoonObj = dofile(SPOON .. "/init.lua")
    spoonObj:init()
    return spoonObj:_start()
  end)
end

print("cycleModifier = ctrl (display cycle on Ctrl release):")
local okCtrl, errCtrl = reloadWith({
  features = {
    monitors = { optionTapCycle = true, cycleModifier = "ctrl" },
    nav = { activator = { kind = "tapModifier", modifier = "rightCmd", onRelease = true } },
  },
})
check("reload with cycleModifier=ctrl", okCtrl, tostring(errCtrl))
setMouse(centerOf(S[1])); resetRec(); timerQ = {}; CLOCK = 400
flags({ ctrl = true }); flags({}); flush()
check("clean ⌃ tap cycles S1 -> S2", approx(mousePos.x, centerOf(S[2]).x), ("x=%.0f"):format(mousePos.x))
setMouse(centerOf(S[1])); resetRec(); timerQ = {}; CLOCK = 500
flags({ alt = true }); flags({}); flush()
check("⌥ tap does NOT cycle when cycleModifier=ctrl", approx(mousePos.x, centerOf(S[1]).x))

print("Clash guard (NAV tap on ⌥ while cycle is also on ⌥ -> cycle disabled):")
local okClash, errClash = reloadWith({
  features = {
    monitors = { optionTapCycle = true, cycleModifier = "alt" },
    nav = { activator = { kind = "tapModifier", modifier = "alt", onRelease = true } },
  },
})
check("reload with clashing alt/alt config", okClash, tostring(errClash))
setMouse(centerOf(S[1])); resetRec(); timerQ = {}; CLOCK = 600
flags({ alt = true }, 58); flags({}, 58); flush()
check("⌥ tap toggles NAV MODE", rec.modalEnters == 1, ("enters=%d"):format(rec.modalEnters))
check("⌥ tap does NOT also cycle displays", approx(mousePos.x, centerOf(S[1]).x), ("x=%.0f"):format(mousePos.x))

print("App shortcut resilience (dead userdata from hs.application.get):")
-- hs.application.get() can return a zombie object for an app that already quit;
-- every method call on it raises. The launcher must fall through to launching.
hs.application.get = function()
  return setmetatable({}, { __index = function() return function() error("dead userdata handle") end end })
end
resetRec(); timerQ = {}
pressModal({}, "c"); flush()
check("dead app handle falls back to launching", rec.launches[1] == "com.openai.chat", table.concat(rec.launches, ","))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
