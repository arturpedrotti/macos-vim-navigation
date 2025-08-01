-- Keyboard-centric navigation for macOS via Hammerspoon.

local hs = hs
local modal = hs.hotkey.modal.new()
local mouse = hs.mouse
local screen = hs.screen
local eventtap = hs.eventtap
local window = hs.window
local app = hs.application
local canvas = hs.canvas
local timer = hs.timer

-- Scroll configuration
local scrollStep = 62
local scrollLargeStep = scrollStep
local scrollInitialDelay = 0.15
local scrollRepeatInterval = 0.05

-- Directional repeat settings
local directionInitialDelay = 0.05
local directionRepeatInterval = 0.15

-- Timer tables
local held = {}
local holdTimers = {}
local repeatInterval = scrollRepeatInterval

-- Natural scrolling
local naturalScroll = hs.mouse.scrollDirection().natural

local function norm(delta)
  if not naturalScroll then return delta end
  return { delta[1] * -1, delta[2] * -1 }
end

-- Dragging state
local dragging = false
local dragMoveFrac = 1/20
local dragMoveLargeFrac = dragMoveFrac * 5

-- Mode state
local mode = "normal"

local function setMousePosition(pos)
  if dragging then
    eventtap.event.newMouseEvent(eventtap.event.types.leftMouseDragged, pos):post()
  end
  mouse.absolutePosition(pos)
end

-- Overlay
local overlay = canvas.new({
  x = screen.mainScreen():frame().x + screen.mainScreen():frame().w - 200,
  y = screen.mainScreen():frame().y + screen.mainScreen():frame().h - 40,
  h = 30, w = 200
}):appendElements({
  type = "rectangle", action = "fill",
  fillColor = { alpha = 0.4, red = 0, green = 0, blue = 0 },
  roundedRectRadii = { xRadius = 8, yRadius = 8 }
}, {
  id = "modeText",
  type = "text", text = "-- NORMAL --",
  textSize = 14, textColor = { white = 1 },
  frame = { x = 0, y = 5, h = 30, w = 200 },
  textAlignment = "center"
})

local visualIndicator = nil

local function showVisualIndicator()
  if visualIndicator then return end
  visualIndicator = canvas.new({
    x = screen.mainScreen():frame().x + screen.mainScreen():frame().w - 210,
    y = screen.mainScreen():frame().y + screen.mainScreen():frame().h - 90,
    w = 200, h = 30
  }):appendElements({
    type = "rectangle", action = "fill",
    fillColor = { red = 0.2, green = 0.2, blue = 1, alpha = 0.5 },
    roundedRectRadii = { xRadius = 8, yRadius = 8 }
  }, {
    type = "text", text = "-- VISUAL MODE --",
    textSize = 14, textColor = { white = 1 },
    frame = { x = 0, y = 5, h = 30, w = 200 },
    textAlignment = "center"
  })
  visualIndicator:show()
end

local function hideVisualIndicator()
  if visualIndicator then
    visualIndicator:delete()
    visualIndicator = nil
  end
end

function modal:entered()
  overlay:show()
end

function modal:exited()
  overlay:hide()
  if mode == "visual" then
    local pos = mouse.absolutePosition()
    if dragging then
      eventtap.event.newMouseEvent(eventtap.event.types.leftMouseUp, pos):post()
      dragging = false
    end
    timer.doAfter(0.05, function() eventtap.leftClick(pos) end)
    mode = "normal"
    hideVisualIndicator()
  end
end

local function bindHeld(mod, key, fn)
  modal:bind(mod, key,
    function()
      fn()
      held[key] = timer.doEvery(repeatInterval, fn)
    end,
    function()
      if held[key] then held[key]:stop(); held[key] = nil end
    end
  )
end

local function bindHoldWithDelay(mod, key, fn, delay, interval)
  modal:bind(mod, key,
    function()
      fn()
      holdTimers[key] = {}
      holdTimers[key].delayTimer = timer.doAfter(delay, function()
        holdTimers[key].repeatTimer = timer.doEvery(interval, fn)
      end)
    end,
    function()
      local t = holdTimers[key]
      if t then
        if t.delayTimer then t.delayTimer:stop() end
        if t.repeatTimer then t.repeatTimer:stop() end
        holdTimers[key] = nil
      end
    end
  )
end

local function moveMouseByFraction(xFrac, yFrac)
  local scr = screen.mainScreen():frame()
  local p = mouse.absolutePosition()
  if mode == "visual" and not dragging then
    dragging = true
    eventtap.event.newMouseEvent(eventtap.event.types.leftMouseDown, p):post()
  end
  setMousePosition({ x = p.x + scr.w * xFrac, y = p.y + scr.h * yFrac })
end

-- Directional movements
local directions = {
  {mod = {}, key = "h", frac = 1/8, dx = -1, dy = 0},
  {mod = {}, key = "l", frac = 1/8, dx = 1, dy = 0},
  {mod = {}, key = "j", frac = 1/8, dx = 0, dy = 1},
  {mod = {}, key = "k", frac = 1/8, dx = 0, dy = -1},
  {mod = {"shift"}, key = "h", frac = 1/2, dx = -1, dy = 0},
  {mod = {"shift"}, key = "l", frac = 1/2, dx = 1, dy = 0},
  {mod = {"shift"}, key = "j", frac = 1/2, dx = 0, dy = 1},
  {mod = {"shift"}, key = "k", frac = 1/2, dx = 0, dy = -1},
}
for _, dir in ipairs(directions) do
  local xFrac, yFrac = dir.dx * dir.frac, dir.dy * dir.frac
  bindHoldWithDelay(dir.mod, dir.key, function() moveMouseByFraction(xFrac, yFrac) end, directionInitialDelay, directionRepeatInterval)
end

local function bindScrollKey(key, initialOffsets, repeatOffsets, initialDragFn, repeatDragFn)
  modal:bind({}, key,
    function()
      if dragging then
        initialDragFn()
      else
        eventtap.scrollWheel(norm(initialOffsets), {}, "pixel")
      end
      holdTimers[key] = {}
      holdTimers[key].delayTimer = timer.doAfter(scrollInitialDelay, function()
        holdTimers[key].repeatTimer = timer.doEvery(scrollRepeatInterval, function()
          if dragging then
            repeatDragFn()
          else
            eventtap.scrollWheel(norm(repeatOffsets), {}, "pixel")
          end
        end)
      end)
    end,
    function()
      local t = holdTimers[key]
      if t then
        if t.delayTimer then t.delayTimer:stop() end
        if t.repeatTimer then t.repeatTimer:stop() end
        holdTimers[key] = nil
      end
    end
  )
end

-- Scroll bindings
bindScrollKey("d", {0, -scrollLargeStep}, {0, -scrollStep},
  function() moveMouseByFraction(0, dragMoveLargeFrac) end,
  function() moveMouseByFraction(0, dragMoveFrac) end)
bindScrollKey("u", {0, scrollLargeStep}, {0, scrollStep},
  function() moveMouseByFraction(0, -dragMoveLargeFrac) end,
  function() moveMouseByFraction(0, -dragMoveFrac) end)
bindScrollKey("w", {-scrollLargeStep, 0}, {-scrollStep, 0},
  function() moveMouseByFraction(mode == "visual" and dragMoveLargeFrac or -dragMoveLargeFrac, 0) end,
  function() moveMouseByFraction(mode == "visual" and dragMoveFrac or -dragMoveFrac, 0) end)
bindScrollKey("b", { scrollLargeStep, 0}, { scrollStep, 0},
  function() moveMouseByFraction(mode == "visual" and -dragMoveLargeFrac or dragMoveLargeFrac, 0) end,
  function() moveMouseByFraction(mode == "visual" and -dragMoveFrac or dragMoveFrac, 0) end)

local largeScrollStep = scrollStep * 8
local largeScrolls = {
  {mod = {"shift"}, key = "u", delta = {0, largeScrollStep}},
  {mod = {"shift"}, key = "d", delta = {0, -largeScrollStep}},
  {mod = {"shift"}, key = "w", delta = {-largeScrollStep, 0}},
  {mod = {"shift"}, key = "b", delta = {largeScrollStep, 0}},
}
for _, sc in ipairs(largeScrolls) do
  bindHoldWithDelay(sc.mod, sc.key, function()
    eventtap.scrollWheel(norm(sc.delta), {}, "pixel")
  end, scrollInitialDelay, scrollRepeatInterval)
end

local function performClicks(count, keepLastDown)
  local pos = mouse.absolutePosition()
  for i = 1, count do
    local down = eventtap.event.newMouseEvent(eventtap.event.types.leftMouseDown, pos)
    down:setProperty(eventtap.event.properties.mouseEventClickState, i)
    down:post()
    if i < count or not keepLastDown then
      local up = eventtap.event.newMouseEvent(eventtap.event.types.leftMouseUp, pos)
      up:post()
    end
  end
end

local function endDragAndClick(pos, action)
  if dragging then
    eventtap.event.newMouseEvent(eventtap.event.types.leftMouseUp, pos):post()
    dragging = false
  end
  if action then
    timer.doAfter(0.05, function()
      eventtap.keyStroke({"cmd"}, action)
      timer.doAfter(0.05, function() eventtap.leftClick(pos) end)
    end)
  else
    timer.doAfter(0.05, function() eventtap.leftClick(pos) end)
  end
end

-- Click bindings
modal:bind({}, "i", function() performClicks(3, false) end)
modal:bind({}, "a", function() eventtap.rightClick(mouse.absolutePosition()) end)

-- Visual mode bindings
modal:bind({}, "v", function()
  local pos = mouse.absolutePosition()
  if mode == "visual" then
    endDragAndClick(pos)
    dragging = false
    mode = "normal"
    hideVisualIndicator()
  else
    dragging = true
    eventtap.event.newMouseEvent(eventtap.event.types.leftMouseDown, pos):post()
    mode = "visual"
    showVisualIndicator()
  end
end)

modal:bind({"shift"}, "v", function()
  local pos = mouse.absolutePosition()
  if mode == "visual" then
    endDragAndClick(pos)
    dragging = false
    mode = "normal"
    hideVisualIndicator()
  else
    performClicks(3, true)
    dragging = true
    mode = "visual"
    showVisualIndicator()
  end
end)

modal:bind({}, "y", function()
  if mode == "visual" and dragging then
    endDragAndClick(mouse.absolutePosition(), "c")
    mode = "normal"
    hideVisualIndicator()
  end
end)

modal:bind({}, "p", function()
  if mode == "visual" and dragging then
    endDragAndClick(mouse.absolutePosition(), "v")
    mode = "normal"
    hideVisualIndicator()
  else
    local pos = mouse.absolutePosition()
    eventtap.leftClick(pos)
    timer.doAfter(0.05, function() eventtap.keyStroke({"cmd"}, "v") end)
  end
end)

modal:bind({"shift"}, "p", function()
  if mode == "visual" and dragging then
    endDragAndClick(mouse.absolutePosition(), "v")
    mode = "normal"
    hideVisualIndicator()
  else
    local pos = mouse.absolutePosition()
    eventtap.leftClick(pos)
    timer.doAfter(0.05, function() eventtap.keyStroke({"cmd"}, "v") end)
  end
end)

-- Focus cycle
local function focusAppOffset(offset)
  local wins = window.visibleWindows()
  local cur = window.focusedWindow()
  for idx, w in ipairs(wins) do
    if w:id() == cur:id() then
      local nextWin = wins[(idx + offset - 1) % #wins + 1]
      if nextWin then nextWin:focus() end
      return
    end
  end
end

modal:bind({"shift"}, "a", function() focusAppOffset(1) end)
modal:bind({"shift"}, "i", function() focusAppOffset(-1) end)

modal:bind({"shift"}, "m", function()
  local f = screen.mainScreen():frame()
  setMousePosition({ x = f.x + f.w/2, y = f.y + f.h/2 })
end)

-- ChatGPT shortcut
modal:bind({}, "c", function()
  if mode == "visual" then
    local pos = mouse.absolutePosition()
    if dragging then
      eventtap.event.newMouseEvent(eventtap.event.types.leftMouseUp, pos):post()
      dragging = false
    end
    timer.doAfter(0.05, function() eventtap.leftClick(pos) end)
    mode = "normal"
    hideVisualIndicator()
  end
  local function clickChatBox(win)
    if win then
      win:raise()
      win:focus()
      local f = win:frame()
      mouse.absolutePosition({ x = f.x + f.w / 2, y = f.y + f.h - 72 })
      timer.doAfter(0.1, function() eventtap.leftClick(mouse.absolutePosition()) end)
    end
  end
  local chatBundleID = "com.openai.chat"
  local runningApp = app.get("ChatGPT")
  if runningApp then
    runningApp:unhide()
    local win = runningApp:mainWindow() or window.get("ChatGPT")
    if win then
      if win:isMinimized() then win:unminimize() end
      clickChatBox(win)
    else
      local openedApp = hs.application.launchOrFocusByBundleID(chatBundleID) or hs.application.open(chatBundleID)
      if openedApp then
        timer.doAfter(1.0, function()
          local newWin = openedApp:mainWindow() or window.get("ChatGPT")
          if newWin then clickChatBox(newWin) else hs.alert.show("ChatGPT window could not be opened") end
        end)
      else
        hs.alert.show("ChatGPT app could not be launched")
      end
    end
  else
    local openedApp = hs.application.launchOrFocusByBundleID(chatBundleID) or hs.application.open(chatBundleID)
    if openedApp then
      timer.doAfter(1.0, function()
        local win = openedApp:mainWindow() or window.get("ChatGPT")
        if win then clickChatBox(win) else hs.alert.show("ChatGPT window did not appear") end
      end)
    else
      hs.alert.show("ChatGPT app could not be launched")
    end
  end
  modal:exit()
end)

-- Vim-style scroll
local gPending = false
local gTimer = nil
local gDoubleDelay = 0.3

local function scrollToTop()
  eventtap.event.newScrollEvent(norm({0, 1000000}), {}, "pixel"):post()
end

local function scrollToBottom()
  eventtap.event.newScrollEvent(norm({0, -1000000}), {}, "pixel"):post()
end

modal:bind({}, "g", function()
  if gPending then
    if gTimer then gTimer:stop(); gTimer = nil end
    gPending = false
    scrollToTop()
  else
    gPending = true
    gTimer = timer.doAfter(gDoubleDelay, function()
      gPending = false
      gTimer = nil
    end)
  end
end)

modal:bind({"shift"}, "g", function()
  gPending = false
  if gTimer then gTimer:stop(); gTimer = nil end
  scrollToBottom()
end)

local gResetTap = eventtap.new({ eventtap.event.types.keyDown }, function(e)
  if gPending then
    local chars = e:getCharacters() or ""
    if chars:lower() ~= "g" then
      gPending = false
      if gTimer then gTimer:stop(); gTimer = nil end
    end
  end
  return false
end)
gResetTap:start()

-- Browser shortcut
modal:bind({}, "o", function()
  local browsers = { "Arc", "Arc Browser", "Google Chrome", "Firefox", "Safari" }
  for _, name in ipairs(browsers) do
    if app.launchOrFocus(name) then return end
  end
  hs.alert.show("No known browsers found to open")
end)

-- Modal entry/exit
hs.hotkey.bind({"ctrl","alt","cmd"}, "space", function() modal:enter() end)
hs.hotkey.bind({}, "f12", function() modal:enter() end)
hs.hotkey.bind({"ctrl"}, "=", function() modal:enter() end)
modal:bind({}, "escape", function() modal:exit() end)
modal:bind({"ctrl"}, "c", function() modal:exit() end)

-- Reload config
hs.hotkey.bind({"alt"}, "r", function()
  hs.reload()
  hs.alert("Reloaded")
end)

-- Option-tap: cycle screens
local optionPressed, optionOtherKey = false, false
local function centerMouseOn(scr)
  if not scr then return end
  if dragging then
    local win = window.focusedWindow()
    if win then win:moveToScreen(scr) end
  end
  local f = scr:frame()
  setMousePosition({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
end

optionFlagsWatcher = eventtap.new({ eventtap.event.types.flagsChanged }, function(e)
  local f = e:getFlags()
  if f.alt and not optionPressed then
    optionPressed = true
    optionOtherKey = false
  elseif not f.alt and optionPressed then
    optionPressed = false
    if not optionOtherKey then
      local currentScr = mouse.getCurrentScreen()
      local allScr = hs.screen.allScreens()
      table.sort(allScr, function(a,b) return a:frame().x < b:frame().x end)
      local currentIndex = 1
      for i, s in ipairs(allScr) do
        if s:id() == currentScr:id() then currentIndex = i; break end
      end
      local nextIndex = (currentIndex % #allScr) + 1
      centerMouseOn(allScr[nextIndex])
    end
  end
end)
optionFlagsWatcher:start()

optionKeyWatcher = eventtap.new({ eventtap.event.types.keyDown }, function(e)
  if optionPressed then optionOtherKey = true end
  return false
end)
optionKeyWatcher:start()

-- Control-tap: click bottom
local ctrlPressed, ctrlOtherKey = false, false
local function clickBottom(scr)
  if not scr then return end
  if dragging then
    local win = window.focusedWindow()
    if win then win:moveToScreen(scr) end
  end
  local f = scr:frame()
  local pos = { x = f.x + f.w / 2, y = f.y + f.h - 80 }
  setMousePosition(pos)
  if not dragging then eventtap.leftClick(pos) end
end

ctrlFlagsWatcher = eventtap.new({ eventtap.event.types.flagsChanged }, function(e)
  local f = e:getFlags()
  if f.ctrl and not ctrlPressed then
    ctrlPressed = true
    ctrlOtherKey = false
  elseif not f.ctrl and ctrlPressed then
    ctrlPressed = false
    if not ctrlOtherKey then clickBottom(mouse.getCurrentScreen()) end
  end
end)
ctrlFlagsWatcher:start()

ctrlKeyWatcher = eventtap.new({ eventtap.event.types.keyDown }, function(e)
  if ctrlPressed then ctrlOtherKey = true end
  return false
end)
ctrlKeyWatcher:start()

-- End of configuration.

-- Credit: Artur Grochau – github.com/arturpedrotti