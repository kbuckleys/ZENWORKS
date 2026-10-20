-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- DEFAULTS
-- Kept in defaults.lua, which oracle's Default Apps section writes. Guarded:
-- a missing or broken file must not take every bind below down with it.
local ok, defaults = pcall(require, "lua.defaults")
if not ok or type(defaults) ~= "table" then defaults = {} end

local term = (defaults.terminal and defaults.terminal ~= "") and defaults.terminal or "kitty"
-- the browser chosen there, or whatever the system has as its default
local web = (defaults.browser and defaults.browser ~= "")
	and ("gtk-launch " .. defaults.browser)
	or "sh -c 'gtk-launch \"$(xdg-settings get default-web-browser)\"'"

-- KEYS
-- Every bind below is bind(id, keys, label, action, opts). The keys written
-- here are its default; keys.lua, which oracle's Shortcuts section writes,
-- names only the ones moved off it (id = "SUPER + K"), and "" there turns
-- one off. Oracle reads THIS file for the list, the labels and the defaults,
-- and the `-- NAME` heading above a run of binds is the group it shows them
-- under — so keep each bind( on a line of its own. Guarded like defaults.lua.
local kok, keys = pcall(require, "lua.keys")
if not kok or type(keys) ~= "table" then keys = {} end

local function bind(id, chord, label, action, opts)
	local k = keys[id]
	if type(k) == "string" then chord = k end
	if chord == "" then return end
	opts = opts or {}
	opts.description = label
	hl.bind(chord, action, opts)
end

-- While oracle waits for a new chord, hyprland is in this submap. It binds
-- next to nothing, so Super+anything reaches oracle instead of being acted
-- on; oracle resets it the moment it has the keys, or after ten seconds.
-- The one bind is there because hyprland will not register an empty
-- submap, and it is a way out: F24, which no one presses by accident.
hl.define_submap("oracle-keys", function()
	hl.bind("F24", hl.dsp.submap("reset"))
end)

-- SYSTEM
bind("shutdown",  "SUPER + SHIFT + ESCAPE",  "Shut down",  hl.dsp.exec_cmd("hyprshutdown"), { locked = true })

-- APPS
bind("terminal",      "SUPER + RETURN",     "Open the terminal",         hl.dsp.exec_cmd(term))
bind("browser",       "SUPER + B",          "Open the browser",          hl.dsp.exec_cmd(web))
bind("cynosure",      "SUPER + SPACE",      "Cynosure, the launcher",    hl.dsp.exec_cmd("qs ipc call Cynosure toggle"))
bind("terminus",      "SUPER + E",          "Terminus, a new window",    hl.dsp.exec_cmd("qs ipc call Terminus spawn ''"))
bind("folio",         "SUPER + C",          "Folio, the clipboard",      hl.dsp.exec_cmd("qs ipc call Folio toggle"))
bind("metis",         "SUPER + SHIFT + C",  "Metis, the calculator",     hl.dsp.exec_cmd("qs ipc call Metis toggle"))
bind("artemis",       "SUPER + S",          "Artemis, file search",      hl.dsp.exec_cmd("qs ipc call Artemis toggle"))
bind("ideoEmoji",     "SUPER + J",          "Ideo, emoji",               hl.dsp.exec_cmd("qs ipc call Ideo emoji"))
bind("ideoNerd",      "SUPER + SHIFT + J",  "Ideo, nerd glyphs",         hl.dsp.exec_cmd("qs ipc call Ideo nerd"))
bind("calypso",       "SUPER + V",          "Calypso, Quick Access",     hl.dsp.exec_cmd("qs ipc call Calypso toggle"))
bind("calypsoWin",    "SUPER + SHIFT + V",  "Calypso, the window",       hl.dsp.exec_cmd("qs ipc call Calypso window"))
bind("clio",          "SUPER + O",          "Clio, notes",               hl.dsp.exec_cmd("qs ipc call Clio open"))
bind("zeus",          "SUPER + K",          "Zeus, the system monitor",  hl.dsp.exec_cmd("qs ipc call Zeus toggle"))
bind("lexi",          "SUPER + D",          "Lexi, the dictionary",      hl.dsp.exec_cmd("qs ipc call Lexi toggle"))
bind("picasso",       "SUPER + SHIFT + B",  "Picasso, the viewer",       hl.dsp.exec_cmd("qs ipc call Picasso toggle"))
bind("ceresStore",    "SUPER + P",          "Ceres, the store",          hl.dsp.exec_cmd("qs ipc call Ceres toggleWindow store"))
bind("ceresUpdates",  "SUPER + SHIFT + P",  "Ceres, updates",            hl.dsp.exec_cmd("qs ipc call Ceres toggleWindow updates"))

-- CAPTURE
bind("shotScreen",  "PRINT",                  "Screenshot, the screen",       hl.dsp.exec_cmd("qs ipc call Picasso shot screen"))
bind("shotWindow",  "SUPER + PRINT",          "Screenshot, a window",         hl.dsp.exec_cmd("qs ipc call Picasso shot window"))
bind("shotPlain",   "SUPER + ALT + PRINT",    "Screenshot, a window, plain",  hl.dsp.exec_cmd("qs ipc call Picasso shot window-plain"))
bind("shotRegion",  "SUPER + SHIFT + PRINT",  "Screenshot, a region",         hl.dsp.exec_cmd("qs ipc call Picasso shot region"))
bind("picker",      "SUPER + CONTROL + P",    "Pick a color",                 hl.dsp.exec_cmd("qs ipc call Picasso pick"))

-- WORKSPACES
bind("special",    "SUPER + GRAVE",          "Show or hide the special workspace",        hl.dsp.workspace.toggle_special("special"))
bind("ws1",        "SUPER + 1",              "Go to workspace 1",                         hl.dsp.focus({ workspace = 1 }))
bind("ws2",        "SUPER + 2",              "Go to workspace 2",                         hl.dsp.focus({ workspace = 2 }))
bind("ws3",        "SUPER + 3",              "Go to workspace 3",                         hl.dsp.focus({ workspace = 3 }))
bind("ws4",        "SUPER + 4",              "Go to workspace 4",                         hl.dsp.focus({ workspace = 4 }))
bind("ws5",        "SUPER + 5",              "Go to workspace 5",                         hl.dsp.focus({ workspace = 5 }))

local function move_and_center(ws)
	hl.dispatch(hl.dsp.window.move({ workspace = ws }))
	local win = hl.get_active_window()
	if win and win.floating then
		hl.dispatch(hl.dsp.window.center())
	end
end

bind("toSpecial",  "SUPER + SHIFT + GRAVE",  "Move the window to the special workspace",  function() move_and_center("special:special") end)
bind("toWs1",      "SUPER + SHIFT + 1",      "Move the window to workspace 1",            function() move_and_center(1) end)
bind("toWs2",      "SUPER + SHIFT + 2",      "Move the window to workspace 2",            function() move_and_center(2) end)
bind("toWs3",      "SUPER + SHIFT + 3",      "Move the window to workspace 3",            function() move_and_center(3) end)
bind("toWs4",      "SUPER + SHIFT + 4",      "Move the window to workspace 4",            function() move_and_center(4) end)
bind("toWs5",      "SUPER + SHIFT + 5",      "Move the window to workspace 5",            function() move_and_center(5) end)

-- WINDOWS
bind("close",       "SUPER + Q",          "Close the window",          hl.dsp.window.close())
bind("kill",        "SUPER + SHIFT + Q",  "Kill the window",           hl.dsp.window.kill())
bind("fullscreen",  "SUPER + SHIFT + F",  "Full screen",               hl.dsp.window.fullscreen())
bind("maximize",    "SUPER + Z",          "Maximize",                  hl.dsp.window.fullscreen({ mode = "maximized" }))
bind("float",       "SUPER + F",          "Float or tile the window",  function()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    hl.dispatch(hl.dsp.window.center())
end)
bind("center",      "SUPER + SHIFT + W",  "Center the window",         hl.dsp.window.center())
bind("pseudo",      "SUPER + W",          "Pseudotile",                hl.dsp.window.pseudo())
bind("split",       "SUPER + X",          "Turn the split",            hl.dsp.layout("togglesplit"))

-- FOCUS
bind("focusRight",  "SUPER + RIGHT",        "Focus right",      hl.dsp.focus({ direction = "r" }))
bind("focusDown",   "SUPER + DOWN",         "Focus down",       hl.dsp.focus({ direction = "d" }))
bind("focusLeft",   "SUPER + LEFT",         "Focus left",       hl.dsp.focus({ direction = "l" }))
bind("focusUp",     "SUPER + UP",           "Focus up",         hl.dsp.focus({ direction = "u" }))

bind("cycle",       "SUPER + TAB",          "Next window",      function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
end)

bind("cycleBack",   "SUPER + SHIFT + TAB",  "Previous window",  function()
    local ws = hl.get_active_workspace()
    if not ws then return end

    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "bottom" }))

    local top
    for _, win in ipairs(hl.get_windows({ workspace = ws, mapped = true })) do
        if not win.hidden then top = win end
    end
    if top then
        hl.dispatch(hl.dsp.focus({ window = top }))
    end
end)

-- MOVE & RESIZE
bind("swapRight",  "SUPER + ALT + RIGHT",      "Swap the window right",  hl.dsp.window.swap({ direction = "r" }))
bind("swapDown",   "SUPER + ALT + DOWN",       "Swap the window down",   hl.dsp.window.swap({ direction = "d" }))
bind("swapLeft",   "SUPER + ALT + LEFT",       "Swap the window left",   hl.dsp.window.swap({ direction = "l" }))
bind("swapUp",     "SUPER + ALT + UP",         "Swap the window up",     hl.dsp.window.swap({ direction = "u" }))

bind("growRight",  "SUPER + CONTROL + RIGHT",  "Wider",                  hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { repeating = true })
bind("growDown",   "SUPER + CONTROL + DOWN",   "Taller",                 hl.dsp.window.resize({ x = 0, y = 100, relative = true }), { repeating = true })
bind("growLeft",   "SUPER + CONTROL + LEFT",   "Narrower",               hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { repeating = true })
bind("growUp",     "SUPER + CONTROL + UP",     "Shorter",                hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { repeating = true })

bind("drag",       "SUPER + mouse:272",        "Drag a window",          hl.dsp.window.drag(), { mouse = true })
bind("resize",     "SUPER + mouse:273",        "Resize a window",        hl.dsp.window.resize(), { mouse = true })

-- GROUPS
bind("group",      "SUPER + SHIFT + G",              "Group or ungroup",             hl.dsp.group.toggle())
bind("groupLock",  "SUPER + G",                      "Lock the group",               hl.dsp.group.lock_active({ action = "toggle" }))
bind("groupPrev",  "ALT + SHIFT + TAB",              "Previous in the group",        hl.dsp.group.prev(), { repeating = true })
bind("groupNext",  "ALT + TAB",                      "Next in the group",            hl.dsp.group.next(), { repeating = true })

bind("intoRight",  "SUPER + SHIFT + ALT + RIGHT",    "Into the group to the right",  hl.dsp.window.move({ into_group = "r" }))
bind("intoDown",   "SUPER + SHIFT + ALT + DOWN",     "Into the group below",         hl.dsp.window.move({ into_group = "d" }))
bind("intoLeft",   "SUPER + SHIFT + ALT + LEFT",     "Into the group to the left",   hl.dsp.window.move({ into_group = "l" }))
bind("intoUp",     "SUPER + SHIFT + ALT + UP",       "Into the group above",         hl.dsp.window.move({ into_group = "u" }))

-- SUPER + SHIFT + CONTROL + arrows is smart-move.lua's snap-to-edge
bind("outRight",   "SUPER + CONTROL + ALT + RIGHT",  "Out of the group, right",      hl.dsp.window.move({ out_of_group = true }))
bind("outDown",    "SUPER + CONTROL + ALT + DOWN",   "Out of the group, down",       hl.dsp.window.move({ out_of_group = true }))
bind("outLeft",    "SUPER + CONTROL + ALT + LEFT",   "Out of the group, left",       hl.dsp.window.move({ out_of_group = true }))
bind("outUp",      "SUPER + CONTROL + ALT + UP",     "Out of the group, up",         hl.dsp.window.move({ out_of_group = true }))

-- MEDIA
bind("volUp",      "SUPER + EQUAL",          "Volume up",       hl.dsp.exec_cmd("pamixer -i 1"), { repeating = true })
bind("volDown",    "SUPER + MINUS",          "Volume down",     hl.dsp.exec_cmd("pamixer -d 1"), { repeating = true })
bind("mute",       "SUPER + 0",              "Mute",            hl.dsp.exec_cmd("pamixer -t"))
bind("next",       "SUPER + SHIFT + EQUAL",  "Next track",      hl.dsp.exec_cmd("playerctl next"))
bind("playPause",  "SUPER + SHIFT + MINUS",  "Play or pause",   hl.dsp.exec_cmd("playerctl play-pause"))
bind("previous",   "SUPER + SHIFT + 0",      "Previous track",  hl.dsp.exec_cmd("playerctl previous"))
