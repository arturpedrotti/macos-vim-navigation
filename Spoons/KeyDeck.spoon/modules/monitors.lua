-- Multi-monitor management. Keyboard-only screen and window focus:
--   * bare cycleModifier tap (⌥ default) -> cycle pointer to the next screen
--   * cycleModifier + d / u              -> scroll half-page globally (no NAV MODE)
--   * Option + jumpKeys                  -> center pointer on monitor N
--   * Option + jumpClickKeys             -> center on monitor N and click to focus
--   * Option + parkKeys                  -> park pointer at monitor N's bottom-right
--   * focusLeft / focusRight             -> focus the window on the left/right screen
--
-- The modifier tap uses an on-release, idle-guarded watcher so it never clobbers
-- regular modifier shortcuts (e.g. ⌥+Cmd+J): the cycle only fires if no other
-- key was pressed and the keyboard has been idle for optionReleaseIdleSeconds.
local M = {}

function M.setup(ctx)
  local hs, mouse, eventtap, screen, window, timer =
    ctx.hs, ctx.mouse, ctx.eventtap, ctx.screen, ctx.window, ctx.timer
  local feat = ctx.cfg.features.monitors
  local t = ctx.cfg.tuning

  -- Physical (non-virtual) screens, sorted left-to-right. Virtual displays such
  -- as BetterDisplay's are identified by name substrings in skipVirtualDisplayPattern.
  local virtualTokens = {}
  for tok in tostring(feat.skipVirtualDisplayPattern or ""):gmatch("[^|]+") do
    table.insert(virtualTokens, tok)
  end
  local function getPhysicalScreens()
    local physical = {}
    for _, scr in ipairs(hs.screen.allScreens()) do
      local name = scr:name() or ""
      local isVirtual = false
      for _, tok in ipairs(virtualTokens) do
        if name:find(tok, 1, true) then isVirtual = true; break end
      end
      if not isVirtual then table.insert(physical, scr) end
    end
    table.sort(physical, function(a, b) return a:frame().x < b:frame().x end)
    return physical
  end

  local function centerMouseOn(scr)
    if not scr then return end
    local f = scr:frame()
    ctx.setMousePosition({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
  end

  -- ---- Modifier-release screen cycle + modifier+D/U scroll --------------------
  -- The modifier is configurable (cycleModifier: "alt" | "ctrl" | "cmd",
  -- Option by default); the release/idle guard logic is identical for all.
  if feat.optionTapCycle or feat.optionScroll then
    local cycleMod = feat.cycleModifier or "alt"
    local function otherModsHeld(f)
      for _, m in ipairs({ "cmd", "alt", "ctrl", "shift" }) do
        if m ~= cycleMod and f[m] then return true end
      end
      return false
    end
    local optionOtherKey, optionHoldActive = false, false
    local pendingReleaseTimer = nil
    local lastOptionKeyTime = 0

    ctx.optionFlagsWatcher = eventtap.new({ eventtap.event.types.flagsChanged }, function(e)
      local f = e:getFlags()
      if f[cycleMod] and not optionHoldActive then
        optionHoldActive = true
        -- Pressed while another modifier is already down -> chorded, not a tap.
        optionOtherKey = otherModsHeld(f)
        if pendingReleaseTimer then pendingReleaseTimer:stop(); pendingReleaseTimer = nil end
      elseif f[cycleMod] and optionHoldActive then
        -- A second modifier chorded in mid-hold (even if released before the
        -- cycle modifier) dirties the tap, same as a normal key would.
        if otherModsHeld(f) then optionOtherKey = true end
      elseif not f[cycleMod] and optionHoldActive then
        optionHoldActive = false
        local idle = timer.secondsSinceEpoch() - lastOptionKeyTime
        if feat.optionTapCycle and not optionOtherKey and idle > t.optionReleaseIdleSeconds then
          pendingReleaseTimer = timer.doAfter(0.05, function()
            pendingReleaseTimer = nil
            if not optionHoldActive then
              local cur = mouse.getCurrentScreen()
              local all = getPhysicalScreens()
              local idx = 1
              for i, s in ipairs(all) do if s:id() == cur:id() then idx = i; break end end
              centerMouseOn(all[(idx % #all) + 1])
            end
          end)
        elseif pendingReleaseTimer then
          pendingReleaseTimer:stop(); pendingReleaseTimer = nil
        end
      end
    end)
    ctx.optionFlagsWatcher:start()

    ctx.optionKeyWatcher = eventtap.new({ eventtap.event.types.keyDown }, function(e)
      -- EVERY keyDown refreshes the idle clock (documented behavior: a tap
      -- within optionReleaseIdleSeconds of any typing must not cycle) — one
      -- clock read per keypress, cheap enough to run unconditionally.
      lastOptionKeyTime = timer.secondsSinceEpoch()
      if optionHoldActive or pendingReleaseTimer then
        local f = e:getFlags()
        if feat.optionScroll and f[cycleMod] and not otherModsHeld(f) then
          local kc = e:getKeyCode()
          if kc == hs.keycodes.map.d then
            optionOtherKey = true
            eventtap.scrollWheel({ 0, -t.optionScrollAmount }, {}, "pixel")
            return true
          elseif kc == hs.keycodes.map.u then
            optionOtherKey = true
            eventtap.scrollWheel({ 0, t.optionScrollAmount }, {}, "pixel")
            return true
          end
        end
        optionOtherKey = true
        if pendingReleaseTimer then pendingReleaseTimer:stop(); pendingReleaseTimer = nil end
      end
      return false
    end)
    ctx.optionKeyWatcher:start()
  end

  -- ---- Option + number: jump / jump+click / park -----------------------------
  local function jumpTo(index, click)
    local all = getPhysicalScreens()
    local scr = all[index]
    if not scr then return end
    local f = scr:frame()
    local pos = { x = f.x + f.w / 2, y = f.y + f.h / 2 }
    ctx.setMousePosition(pos)
    if click then timer.doAfter(0.05, function() eventtap.leftClick(pos) end) end
  end
  local function parkAt(index)
    local all = getPhysicalScreens()
    local scr = all[index]
    if not scr then return end
    local f = scr:frame()
    local p = feat.parkPadding or 30
    ctx.setMousePosition({ x = f.x + f.w - p, y = f.y + f.h - p })
  end
  -- A config-supplied key is bindable only if it's a non-empty string. An empty
  -- string means "unbound" (e.g. cleared by the GUI) — Lua treats "" as truthy, so
  -- guard explicitly to avoid hs.hotkey.bind erroring on an invalid key.
  local function bindable(k) return type(k) == "string" and #k > 0 end

  for i, key in ipairs(feat.jumpKeys or {}) do
    if bindable(key) then ctx.bindGlobal({ "alt" }, key, function() jumpTo(i, false) end) end
  end
  for i, key in ipairs(feat.jumpClickKeys or {}) do
    if bindable(key) then ctx.bindGlobal({ "alt" }, key, function() jumpTo(i, true) end) end
  end
  for i, key in ipairs(feat.parkKeys or {}) do
    if bindable(key) then ctx.bindGlobal({ "alt" }, key, function() parkAt(i) end) end
  end

  -- ---- Directional window/screen focus ---------------------------------------
  local function focusWindowInDirection(direction)
    local currentWin = window.focusedWindow()
    if not currentWin then hs.alert.show("No window focused"); return end
    local currentScreen = currentWin:screen()
    -- getPhysicalScreens() skips virtual displays and sorts a fresh copy —
    -- never sort hs.screen.allScreens()'s live table in place.
    local allScreens = getPhysicalScreens()
    local visible = hs.fnutils.filter(window.orderedWindows(), function(w)
      return not w:isMinimized() and w:isVisible() and w:isStandard()
    end)
    if #visible <= 1 then hs.alert.show("No other visible windows"); return end

    if #allScreens > 1 then
      local idx = 1
      for i, s in ipairs(allScreens) do if s:id() == currentScreen:id() then idx = i; break end end
      local target
      if direction == "left" then
        target = idx > 1 and allScreens[idx - 1] or allScreens[#allScreens]
      else
        target = idx < #allScreens and allScreens[idx + 1] or allScreens[1]
      end
      local targetWin
      for _, w in ipairs(visible) do
        if w:screen():id() == target:id() and w:id() ~= currentWin:id() then targetWin = w; break end
      end
      if targetWin then
        targetWin:focus()
      else
        local f = target:frame()
        mouse.absolutePosition({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
        hs.alert.show("No window on " .. direction .. " screen")
      end
    else
      -- Single monitor: cycle windows by horizontal position.
      local cf = currentWin:frame()
      local currentX = cf.x + cf.w / 2
      local screenWins = {}
      for _, w in ipairs(visible) do
        if w:screen():id() == currentScreen:id() and w:id() ~= currentWin:id() then
          local f = w:frame()
          table.insert(screenWins, { window = w, x = f.x + f.w / 2 })
        end
      end
      if #screenWins == 0 then hs.alert.show("No other windows on screen"); return end
      table.sort(screenWins, function(a, b) return a.x < b.x end)
      local targetWin
      if direction == "left" then
        for i = #screenWins, 1, -1 do if screenWins[i].x < currentX then targetWin = screenWins[i].window; break end end
        targetWin = targetWin or screenWins[#screenWins].window
      else
        for i = 1, #screenWins do if screenWins[i].x > currentX then targetWin = screenWins[i].window; break end end
        targetWin = targetWin or screenWins[1].window
      end
      if targetWin then targetWin:focus() end
    end
  end
  if feat.focusLeft and bindable(feat.focusLeft.key) then
    ctx.bindGlobal(feat.focusLeft.mods or {}, feat.focusLeft.key, function() focusWindowInDirection("left") end)
  end
  if feat.focusRight and bindable(feat.focusRight.key) then
    ctx.bindGlobal(feat.focusRight.mods or {}, feat.focusRight.key, function() focusWindowInDirection("right") end)
  end

  -- Move the pointer to the next / previous physical display (wrap-around).
  local function cycleDisplay(dir)
    local all = getPhysicalScreens()
    if #all == 0 then return end
    local cur = mouse.getCurrentScreen()
    local idx = 1
    for i, s in ipairs(all) do if s:id() == cur:id() then idx = i; break end end
    local nextIdx = ((idx - 1 + dir) % #all) + 1
    centerMouseOn(all[nextIdx])
  end
  if feat.nextDisplay and bindable(feat.nextDisplay.key) then
    ctx.bindGlobal(feat.nextDisplay.mods or {}, feat.nextDisplay.key, function() cycleDisplay(1) end)
  end
  if feat.prevDisplay and bindable(feat.prevDisplay.key) then
    ctx.bindGlobal(feat.prevDisplay.mods or {}, feat.prevDisplay.key, function() cycleDisplay(-1) end)
  end
end

return M
