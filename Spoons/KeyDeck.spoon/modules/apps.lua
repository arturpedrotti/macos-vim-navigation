-- Per-app launch/focus shortcuts (NAV MODE), driven entirely by the cfg.apps list.
-- This replaces the original four near-identical hardcoded blocks (ChatGPT, VSCode,
-- Arc, Atlas, Teams) with one loop. Each entry picks a click strategy by name:
--   "center" -> click middle of the window
--   "bottom" -> click near the bottom-center (e.g. ChatGPT's input box)
--   "none"   -> raise/focus only, no click
local M = {}

function M.setup(ctx)
  local modal, mouse, eventtap, timer, app, window =
    ctx.modal, ctx.mouse, ctx.eventtap, ctx.timer, ctx.app, ctx.window

  -- Compute the click point for a window frame given a strategy.
  local function clickPoint(f, target)
    if target == "bottom" then
      return { x = f.x + f.w / 2, y = f.y + f.h - 72 }
    end
    return { x = f.x + f.w / 2, y = f.y + f.h / 2 } -- "center"
  end

  -- Focus a window and (optionally) click it per the strategy.
  local function focusAndClick(win, target)
    if not win then return end
    win:raise()
    win:focus()
    if target == "none" then return end
    local f = win:frame()
    local pt = clickPoint(f, target)
    mouse.absolutePosition(pt)
    timer.doAfter(0.2, function() eventtap.leftClick(mouse.absolutePosition()) end)
  end

  -- Find a running app by any of its candidate names.
  local function findRunning(names)
    for _, name in ipairs(names or {}) do
      local a = app.get(name)
      if a then return a end
    end
    return nil
  end

  local function activate(entry)
    local target = entry.clickTarget or "center"
    local label = (entry.names and entry.names[1]) or entry.bundleID or "App"

    local function openFresh()
      local opened = hs.application.launchOrFocusByBundleID(entry.bundleID)
        or hs.application.open(entry.bundleID)
      if opened then
        timer.doAfter(2.0, function()
          local win = (type(opened) == "userdata" and opened.mainWindow and opened:mainWindow())
            or window.get(label)
          if win then focusAndClick(win, target)
          else hs.alert.show(label .. " window did not appear") end
        end)
      else
        hs.alert.show(label .. " could not be launched")
      end
    end

    -- hs.application.get() can return dead userdata for an app that already
    -- quit; any method call on it raises. Treat a raising handle exactly like
    -- "not running" and fall through to the launch path.
    local running = findRunning(entry.names)
    local focused = false
    if running then
      local ok, hadWindow = pcall(function()
        running:unhide()
        local win = running:mainWindow()
        if not win then return false end
        if win:isMinimized() then win:unminimize() end
        focusAndClick(win, target)
        return true
      end)
      focused = ok and hadWindow == true
    end
    if not focused then openFresh() end

    if entry.exitNav ~= false then modal:exit() end
  end

  for _, entry in ipairs(ctx.cfg.apps or {}) do
    if type(entry.key) == "string" and #entry.key > 0 then
      modal:bind(entry.mods or {}, entry.key, function() activate(entry) end)
    end
  end
end

return M
