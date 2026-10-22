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
	-- a second action for the same keys coming up (the cheat sheet's peek)
	local up = opts.onRelease
	opts.onRelease = nil
	hl.bind(chord, action, opts)
	if up then hl.bind(chord, up, { release = true, description = label }) end
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
bind("lock",        "SUPER + ESCAPE",          "Lock the screen",         hl.dsp.exec_cmd("qs ipc call Cerberus lock"))
-- locks, then the screens go off a second late: base.lua wakes them on any
-- key event (a mouse move too, by wake.lua), and letting go of these keys
-- is one, so off at once would not last. Woken, they show the lock.
bind("screensOff",  "SUPER + SHIFT + ESCAPE",  "Lock and suspend screen", hl.dsp.exec_cmd([[qs ipc call Cerberus lock; sleep 1; hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })']]))

-- off until given a chord in oracle's Shortcuts
bind("shutdown",    "",                        "Shutdown",                hl.dsp.exec_cmd("hyprshutdown -t 'Shutting down…' -p 'systemctl poweroff'"))
bind("awake",       "",                        "Keep the machine awake",  hl.dsp.exec_cmd("qs ipc call Socordia awake"))
bind("logout",      "",                        "Log out of hyprland",     hl.dsp.exit())

-- hyprshutdown closes every app and then hyprland itself
bind("terminate",   "SUPER + SHIFT + F1",      "Terminate hyprland",      hl.dsp.exec_cmd("hyprshutdown -t 'Leaving Hyprland…'"), { locked = true })

-- APPS
bind("terminal",       "SUPER + RETURN",     "Open the terminal",              hl.dsp.exec_cmd(term))
bind("browser",        "SUPER + B",          "Open the browser",               hl.dsp.exec_cmd(web))
bind("cynosure",       "SUPER + SPACE",      "Cynosure, the launcher",         hl.dsp.exec_cmd("qs ipc call Cynosure toggle"))
-- held, the sheet shows until the keys come up; tapped, it stays open
bind("keysSheet",      "SUPER + SLASH",      "Shortcuts cheat sheet",          hl.dsp.exec_cmd("qs ipc call Keys hold"), { onRelease = hl.dsp.exec_cmd("qs ipc call Keys release") })
bind("terminus",       "SUPER + E",          "Terminus, a new window",         hl.dsp.exec_cmd("qs ipc call Terminus spawn ''"))
bind("folio",          "SUPER + C",          "Folio, the clipboard",           hl.dsp.exec_cmd("qs ipc call Folio toggle"))
bind("metis",          "SUPER + SHIFT + C",  "Metis, the calculator",          hl.dsp.exec_cmd("qs ipc call Metis toggle"))
bind("artemis",        "SUPER + S",          "Artemis, file search",           hl.dsp.exec_cmd("qs ipc call Artemis toggle"))
bind("ideoEmoji",      "SUPER + J",          "Ideo, emoji",                    hl.dsp.exec_cmd("qs ipc call Ideo emoji"))
bind("ideoNerd",       "SUPER + SHIFT + J",  "Ideo, nerd glyphs",              hl.dsp.exec_cmd("qs ipc call Ideo nerd"))
bind("calypso",        "SUPER + V",          "Calypso, Quick Access",          hl.dsp.exec_cmd("qs ipc call Calypso toggle"))
bind("calypsoWin",     "SUPER + SHIFT + V",  "Calypso, the window",            hl.dsp.exec_cmd("qs ipc call Calypso window"))
bind("clio",           "SUPER + O",          "Clio, notes",                    hl.dsp.exec_cmd("qs ipc call Clio open"))
bind("zeus",           "SUPER + K",          "Zeus, the system monitor",       hl.dsp.exec_cmd("qs ipc call Zeus toggle"))
bind("lexi",           "SUPER + D",          "Lexi, the dictionary",           hl.dsp.exec_cmd("qs ipc call Lexi toggle"))
bind("picasso",        "SUPER + SHIFT + B",  "Picasso, the viewer",            hl.dsp.exec_cmd("qs ipc call Picasso toggle"))
bind("ceresStore",     "SUPER + P",          "Ceres, the store",               hl.dsp.exec_cmd("qs ipc call Ceres toggleWindow store"))
bind("ceresUpdates",   "SUPER + SHIFT + P",  "Ceres, updates",                 hl.dsp.exec_cmd("qs ipc call Ceres toggleWindow updates"))

-- off until given a chord in oracle's Shortcuts
bind("oracle",         "",                   "Oracle, the settings",           hl.dsp.exec_cmd("qs ipc call Oracle toggle"))
bind("chronos",        "",                   "Chronos, the calendar",          hl.dsp.exec_cmd("qs ipc call Chronos toggle"))
bind("icarus",         "",                   "Icarus, the desktop menu",       hl.dsp.exec_cmd("qs ipc call Icarus toggle"))
bind("lexiTranslate",  "",                   "Lexi, translate",                hl.dsp.exec_cmd("qs ipc call Lexi translate"))
bind("zeusProcs",      "",                   "Zeus, the processes",            hl.dsp.exec_cmd("qs ipc call Zeus view list"))
bind("zeusNet",        "",                   "Zeus, the connections",          hl.dsp.exec_cmd("qs ipc call Zeus view net"))
bind("zeusSound",      "",                   "Zeus, sound",                    hl.dsp.exec_cmd("qs ipc call Zeus view sound"))
bind("terminusFind",   "",                   "Terminus, find a file by name",  hl.dsp.exec_cmd("qs ipc call Terminus search find"))
bind("terminusGrep",   "",                   "Terminus, search inside files",  hl.dsp.exec_cmd("qs ipc call Terminus search grep"))
bind("clioToday",      "",                   "Clio, today's journal",          hl.dsp.exec_cmd("qs ipc call Clio today"))
bind("clioCapture",    "",                   "Clio, a quick note",             hl.dsp.exec_cmd("qs ipc call Clio capture"))
bind("platoCapture",   "",                   "Plato, the capture note",        hl.dsp.exec_cmd("qs ipc call Plato capture"))
bind("calypsoLock",    "",                   "Calypso, lock every vault",      hl.dsp.exec_cmd("qs ipc call Calypso lock"))
bind("alexandria",     "",                   "Alexandria, the glyphs",         hl.dsp.exec_cmd("qs ipc call Alexandria glyphs ''"))
bind("ceresCheck",     "",                   "Ceres, check for updates",       hl.dsp.exec_cmd("qs ipc call Ceres check"))
bind("pomodoro",       "",                   "Chronos, start a pomodoro",      hl.dsp.exec_cmd("qs ipc call Chronos pomodoro 0"))
bind("timersStop",     "",                   "Chronos, stop the timers",       hl.dsp.exec_cmd("qs ipc call Chronos halt"))
bind("minerva",        "",                   "Minerva, the library",           hl.dsp.exec_cmd("qs ipc call Minerva library"))
bind("hestia",         "",                   "Hestia, services and logs",      hl.dsp.exec_cmd("qs ipc call Hestia open ''"))
bind("hestiaJournal",  "",                   "Hestia, the journal",            hl.dsp.exec_cmd("qs ipc call Hestia journal ''"))
bind("kairos",         "",                   "Screen Time",                    hl.dsp.exec_cmd("qs ipc call Kairos open ''"))
bind("hermes",         "",                   "Hermes, the quick panel",        hl.dsp.exec_cmd("qs ipc call Hermes toggle"))
bind("hermesWin",      "",                   "Hermes, the window",             hl.dsp.exec_cmd("qs ipc call Hermes window ''"))
bind("nightLight",     "",                   "Night light, on or off",         hl.dsp.exec_cmd("qs ipc call Hermes night"))
bind("wifiToggle",     "",                   "Wi-Fi, on or off",               hl.dsp.exec_cmd("qs ipc call Hermes wifi"))
bind("btToggle",       "",                   "Bluetooth, on or off",           hl.dsp.exec_cmd("qs ipc call Hermes bluetooth"))

-- NOTIFICATIONS
-- off until given a chord in oracle's Shortcuts
bind("bell",         "",  "Howler, the bell",               hl.dsp.exec_cmd("qs ipc call Howler toggle"))
bind("dnd",          "",  "Do not disturb, on or off",      hl.dsp.exec_cmd("qs ipc call Howler silent"))
bind("dismiss",      "",  "Put away the toasts on screen",  hl.dsp.exec_cmd("qs ipc call Howler dismiss"))
bind("clearToasts",  "",  "Clear every notification",       hl.dsp.exec_cmd("qs ipc call Howler clear"))

-- CAPTURE
bind("shotScreen",  "PRINT",                  "Screenshot, the screen",              hl.dsp.exec_cmd("qs ipc call Picasso shot screen"))
bind("shotWindow",  "SUPER + PRINT",          "Screenshot, a window",                hl.dsp.exec_cmd("qs ipc call Picasso shot window"))
bind("shotPlain",   "SUPER + ALT + PRINT",    "Screenshot, a window, plain",         hl.dsp.exec_cmd("qs ipc call Picasso shot window-plain"))
bind("shotRegion",  "SUPER + SHIFT + PRINT",  "Screenshot, a region",                hl.dsp.exec_cmd("qs ipc call Picasso shot region"))

-- Argus, the recorder (quickshell/argus/argus.lua): the same keys start a
-- recording and stop the one running
local function record(mode)
	return function() if ZenRecord then ZenRecord(mode) end end
end
bind("recScreen",   "SUPER + R",              "Record, the screen, or stop",         record("full"))
bind("recWindow",   "SUPER + SHIFT + R",      "Record, a window, or stop",           record("window"))
bind("recRegion",   "SUPER + CONTROL + R",    "Record, a region, or stop",           record("region"))

-- off until given a chord in oracle's Shortcuts
bind("recStop",     "",                       "Stop recording",                      record("stop"))
bind("recEdit",     "",                       "Argus, cut the last recording",       hl.dsp.exec_cmd("qs ipc call Argus last"))
bind("slideNext",   "",                       "Background slideshow, the next one",  hl.dsp.exec_cmd("qs ipc call Picasso next"))
bind("picker",      "SUPER + CONTROL + P",    "Pick a color",                        hl.dsp.exec_cmd("qs ipc call Picasso pick"))
bind("ruler",       "",                       "Measure on screen",                   hl.dsp.exec_cmd("qs ipc call Picasso measure"))

-- WORKSPACES
bind("special",    "SUPER + GRAVE",          "Show or hide the special workspace",                hl.dsp.workspace.toggle_special("special"))
bind("ws1",        "SUPER + 1",              "Go to workspace 1",                                 hl.dsp.focus({ workspace = 1 }))
bind("ws2",        "SUPER + 2",              "Go to workspace 2",                                 hl.dsp.focus({ workspace = 2 }))
bind("ws3",        "SUPER + 3",              "Go to workspace 3",                                 hl.dsp.focus({ workspace = 3 }))
bind("ws4",        "SUPER + 4",              "Go to workspace 4",                                 hl.dsp.focus({ workspace = 4 }))
bind("ws5",        "SUPER + 5",              "Go to workspace 5",                                 hl.dsp.focus({ workspace = 5 }))

-- off until given a chord in oracle's Shortcuts
bind("ws6",        "",                       "Go to workspace 6",                                 hl.dsp.focus({ workspace = 6 }))
bind("ws7",        "",                       "Go to workspace 7",                                 hl.dsp.focus({ workspace = 7 }))
bind("ws8",        "",                       "Go to workspace 8",                                 hl.dsp.focus({ workspace = 8 }))
bind("ws9",        "",                       "Go to workspace 9",                                 hl.dsp.focus({ workspace = 9 }))
bind("ws10",       "",                       "Go to workspace 10",                                hl.dsp.focus({ workspace = 10 }))
bind("wsNext",     "",                       "The next workspace in use",                         hl.dsp.focus({ workspace = "e+1" }))
bind("wsPrev",     "",                       "The previous workspace in use",                     hl.dsp.focus({ workspace = "e-1" }))
bind("wsBack",     "",                       "The workspace you were on",                         hl.dsp.focus({ workspace = "previous" }))
bind("wsEmpty",    "",                       "An empty workspace",                                hl.dsp.focus({ workspace = "empty" }))

local function move_and_center(ws)
	hl.dispatch(hl.dsp.window.move({ workspace = ws }))
	local win = hl.get_active_window()
	if win and win.floating then
		hl.dispatch(hl.dsp.window.center())
	end
end

bind("toSpecial",  "SUPER + SHIFT + GRAVE",  "Move the window to the special workspace",          function() move_and_center("special:special") end)
bind("toWs1",      "SUPER + SHIFT + 1",      "Move the window to workspace 1",                    function() move_and_center(1) end)
bind("toWs2",      "SUPER + SHIFT + 2",      "Move the window to workspace 2",                    function() move_and_center(2) end)
bind("toWs3",      "SUPER + SHIFT + 3",      "Move the window to workspace 3",                    function() move_and_center(3) end)
bind("toWs4",      "SUPER + SHIFT + 4",      "Move the window to workspace 4",                    function() move_and_center(4) end)
bind("toWs5",      "SUPER + SHIFT + 5",      "Move the window to workspace 5",                    function() move_and_center(5) end)

-- off until given a chord in oracle's Shortcuts
bind("toWs6",      "",                       "Move the window to workspace 6",                    function() move_and_center(6) end)
bind("toWs7",      "",                       "Move the window to workspace 7",                    function() move_and_center(7) end)
bind("toWs8",      "",                       "Move the window to workspace 8",                    function() move_and_center(8) end)
bind("toWs9",      "",                       "Move the window to workspace 9",                    function() move_and_center(9) end)
bind("toWs10",     "",                       "Move the window to workspace 10",                   function() move_and_center(10) end)
bind("toWsNext",   "",                       "Move the window to the next workspace in use",      function() move_and_center("e+1") end)
bind("toWsPrev",   "",                       "Move the window to the previous workspace in use",  function() move_and_center("e-1") end)
bind("toWsEmpty",  "",                       "Move the window to an empty workspace",             function() move_and_center("empty") end)

-- WINDOWS
bind("close",       "SUPER + Q",          "Close the window",                   hl.dsp.window.close())
bind("kill",        "SUPER + SHIFT + Q",  "Kill the window",                    hl.dsp.window.kill())
bind("fullscreen",  "SUPER + SHIFT + F",  "Full screen",                        hl.dsp.window.fullscreen())
bind("maximize",    "SUPER + Z",          "Maximize",                           hl.dsp.window.fullscreen({ mode = "maximized" }))
bind("float",       "SUPER + F",          "Float or tile the window",           function()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    hl.dispatch(hl.dsp.window.center())
end)
bind("center",      "SUPER + SHIFT + W",  "Center the window",                  hl.dsp.window.center())
bind("pseudo",      "SUPER + W",          "Pseudotile",                         hl.dsp.window.pseudo())
bind("split",       "SUPER + X",          "Turn the split",                     hl.dsp.layout("togglesplit"))

-- off until given a chord in oracle's Shortcuts
bind("pin",         "",                   "Pin the window to every workspace",  hl.dsp.window.pin())
bind("swallow",     "",                   "Swallowing, on or off",              hl.dsp.window.toggle_swallow())

-- FOCUS
bind("focusRight",    "SUPER + RIGHT",        "Focus right",                         hl.dsp.focus({ direction = "r" }))
bind("focusDown",     "SUPER + DOWN",         "Focus down",                          hl.dsp.focus({ direction = "d" }))
bind("focusLeft",     "SUPER + LEFT",         "Focus left",                          hl.dsp.focus({ direction = "l" }))
bind("focusUp",       "SUPER + UP",           "Focus up",                            hl.dsp.focus({ direction = "u" }))

bind("cycle",         "SUPER + TAB",          "Next window",                         function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
end)

bind("cycleBack",     "SUPER + SHIFT + TAB",  "Previous window",                     function()
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

-- off until given a chord in oracle's Shortcuts
bind("focusUrgent",   "",                     "The urgent window, or the last one",  hl.dsp.focus({ urgent_or_last = true }))
bind("focusMonNext",  "",                     "The next monitor",                    hl.dsp.focus({ monitor = "+1" }))
bind("focusMonPrev",  "",                     "The previous monitor",                hl.dsp.focus({ monitor = "-1" }))

-- MOVE & RESIZE
bind("swapRight",  "SUPER + ALT + RIGHT",      "Swap the window right",                    hl.dsp.window.swap({ direction = "r" }))
bind("swapDown",   "SUPER + ALT + DOWN",       "Swap the window down",                     hl.dsp.window.swap({ direction = "d" }))
bind("swapLeft",   "SUPER + ALT + LEFT",       "Swap the window left",                     hl.dsp.window.swap({ direction = "l" }))
bind("swapUp",     "SUPER + ALT + UP",         "Swap the window up",                       hl.dsp.window.swap({ direction = "u" }))

bind("growRight",  "SUPER + CONTROL + RIGHT",  "Wider",                                    hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { repeating = true })
bind("growDown",   "SUPER + CONTROL + DOWN",   "Taller",                                   hl.dsp.window.resize({ x = 0, y = 100, relative = true }), { repeating = true })
bind("growLeft",   "SUPER + CONTROL + LEFT",   "Narrower",                                 hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { repeating = true })
bind("growUp",     "SUPER + CONTROL + UP",     "Shorter",                                  hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { repeating = true })

bind("drag",       "SUPER + mouse:272",        "Drag a window",                            hl.dsp.window.drag(), { mouse = true })
bind("resize",     "SUPER + mouse:273",        "Resize a window",                          hl.dsp.window.resize(), { mouse = true })

-- off until given a chord in oracle's Shortcuts
bind("toMonNext",  "",                         "Move the window to the next monitor",      hl.dsp.window.move({ monitor = "+1" }))
bind("toMonPrev",  "",                         "Move the window to the previous monitor",  hl.dsp.window.move({ monitor = "-1" }))

-- GROUPS
bind("group",      "SUPER + SHIFT + G",              "Group or ungroup",               hl.dsp.group.toggle())
bind("groupLock",  "SUPER + G",                      "Lock the group",                 hl.dsp.group.lock_active({ action = "toggle" }))
bind("groupPrev",  "ALT + SHIFT + TAB",              "Previous in the group",          hl.dsp.group.prev(), { repeating = true })
bind("groupNext",  "ALT + TAB",                      "Next in the group",              hl.dsp.group.next(), { repeating = true })

bind("intoRight",  "SUPER + SHIFT + ALT + RIGHT",    "Into the group to the right",    hl.dsp.window.move({ into_group = "r" }))
bind("intoDown",   "SUPER + SHIFT + ALT + DOWN",     "Into the group below",           hl.dsp.window.move({ into_group = "d" }))
bind("intoLeft",   "SUPER + SHIFT + ALT + LEFT",     "Into the group to the left",     hl.dsp.window.move({ into_group = "l" }))
bind("intoUp",     "SUPER + SHIFT + ALT + UP",       "Into the group above",           hl.dsp.window.move({ into_group = "u" }))

-- SUPER + SHIFT + CONTROL + arrows is smart-move.lua's snap-to-edge
bind("outRight",   "SUPER + CONTROL + ALT + RIGHT",  "Out of the group, right",        hl.dsp.window.move({ out_of_group = true }))
bind("outDown",    "SUPER + CONTROL + ALT + DOWN",   "Out of the group, down",         hl.dsp.window.move({ out_of_group = true }))
bind("outLeft",    "SUPER + CONTROL + ALT + LEFT",   "Out of the group, left",         hl.dsp.window.move({ out_of_group = true }))
bind("outUp",      "SUPER + CONTROL + ALT + UP",     "Out of the group, up",           hl.dsp.window.move({ out_of_group = true }))

-- off until given a chord in oracle's Shortcuts
bind("groupDeny",  "",                               "Keep the window out of groups",  hl.dsp.window.deny_from_group())

-- MEDIA
bind("volUp",      "SUPER + EQUAL",          "Volume up",            hl.dsp.exec_cmd("pamixer -i 1"), { repeating = true })
bind("volDown",    "SUPER + MINUS",          "Volume down",          hl.dsp.exec_cmd("pamixer -d 1"), { repeating = true })
bind("mute",       "SUPER + 0",              "Mute",                 hl.dsp.exec_cmd("pamixer -t"))
bind("next",       "SUPER + SHIFT + EQUAL",  "Next track",           hl.dsp.exec_cmd("playerctl next"))
bind("playPause",  "SUPER + SHIFT + MINUS",  "Play or pause",        hl.dsp.exec_cmd("playerctl play-pause"))
bind("previous",   "SUPER + SHIFT + 0",      "Previous track",       hl.dsp.exec_cmd("playerctl previous"))

-- through hermes, so every screen it can dim moves and the OSD shows it
bind("brightUp",   "XF86MonBrightnessUp",    "Brightness up",        hl.dsp.exec_cmd("qs ipc call Hermes brightness 5"), { repeating = true })
bind("brightDown", "XF86MonBrightnessDown",  "Brightness down",      hl.dsp.exec_cmd("qs ipc call Hermes brightness -5"), { repeating = true })

-- off until given a chord in oracle's Shortcuts
bind("micMute",    "",                       "Mute the microphone",  hl.dsp.exec_cmd("pamixer --default-source -t"))
bind("stop",       "",                       "Stop playing",         hl.dsp.exec_cmd("playerctl stop"))
