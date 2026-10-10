-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- NEW WINDOWS OPEN WHERE THE FOCUS IS, NOT BEHIND IT
-- Hyprland maps a new window onto the focused monitor's special workspace
-- whenever one is open there, whichever window actually has the focus
-- (mapWindow, src/desktop/view/Window.cpp). The focused MONITOR follows the
-- cursor, the focused window does not: with the special shown on one screen
-- and the keyboard on a window on the other, a cursor resting over the
-- special's screen sent terminus into the special. So: remember where the
-- focus was before each change, and a window that lands in a special the
-- focus was not in goes to the workspace that had it, on its own monitor.

local now, before = nil, nil

local function where(w)
	local ws = w and w.workspace
	if not ws then return nil end
	return { address = w.address, id = ws.id, special = ws.special }
end

hl.on("window.active", function(w)
	if not w then
		before, now = now, nil
		return
	end
	if now and now.address == w.address then return end
	before, now = now, where(w)
end)

hl.on("window.open", function(w)
	if not (w and w.workspace and w.workspace.special) then return end
	-- the focus as it was before this window arrived (it may already
	-- have taken it)
	local was = (now and now.address == w.address) and before or now
	if not was or was.special then return end
	hl.dispatch(hl.dsp.window.move({ workspace = was.id, follow = false,
	                                 window = "address:" .. w.address }))
	hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address }))
end)
