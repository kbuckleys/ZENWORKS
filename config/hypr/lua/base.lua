-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- ENV
-- Nvidia cache limit set to 20 GB
hl.env("__GL_SHADER_DISK_CACHE_SIZE", "21474836480")
hl.env("__GL_SHADER_DISK_CACHE_SKIP_CLEANUP", "1")
hl.env("QSG_RENDER_LOOP", "threaded")

-- FLATPAK'S APPS IN THE LAUNCHER: Flatpak exports their desktop entries
-- under its own share directories, which /etc/profile.d/flatpak.sh adds to
-- XDG_DATA_DIRS for a login shell — and a session started without one never
-- saw them. Added here, ahead of the system's, once only (a reload runs this
-- again with what it set). Harmless with no Flatpak: the directories are not
-- there, and nothing looks in them.
local dataDirs = os.getenv("XDG_DATA_DIRS")
if not dataDirs or dataDirs == "" then dataDirs = "/usr/local/share:/usr/share" end
local fpUser = os.getenv("HOME") .. "/.local/share/flatpak/exports/share"
local fpSystem = "/var/lib/flatpak/exports/share"
for _, d in ipairs({ fpSystem, fpUser }) do
	if not (":" .. dataDirs .. ":"):find(":" .. d .. ":", 1, true) then
		dataDirs = d .. ":" .. dataDirs
	end
end
hl.env("XDG_DATA_DIRS", dataDirs)

-- DEFAULT PROGRAMS, for command-line tools: the editor git and sudoedit open,
-- and the browser a link is handed to. Chosen in oracle's Default Apps and
-- kept in defaults.lua; guarded like binds.lua, so a broken file costs these
-- two variables and nothing else.
--
-- plato's launcher goes on PATH, so `plato file` works in any terminal and
-- as $EDITOR. As $EDITOR it is `plato --wait`: plato is a window, and git
-- reads the file back the moment its editor returns. Once only — a reload
-- runs this again with the PATH it set the first time.
local xdg = os.getenv("XDG_CONFIG_HOME")
local platoBin = ((xdg and xdg ~= "") and xdg or (os.getenv("HOME") .. "/.config")) .. "/quickshell/plato/bin"
local path = os.getenv("PATH") or "/usr/local/bin:/usr/bin"
if not (":" .. path .. ":"):find(":" .. platoBin .. ":", 1, true) then
	hl.env("PATH", platoBin .. ":" .. path)
end

local ok, defaults = pcall(require, "lua.defaults")
if ok and type(defaults) == "table" then
	if defaults.editor and defaults.editor ~= "" then
		local editor = defaults.editor == "plato" and "plato --wait" or defaults.editor
		hl.env("EDITOR", editor)
		hl.env("VISUAL", editor)
	end
	if defaults.browser and defaults.browser ~= "" then
		hl.env("BROWSER", "gtk-launch " .. defaults.browser)
	end
end

-- INPUT: the keyboard, the mouse, the touchpad, the tablet, and how focus
-- follows the pointer. Chosen in oracle's Input section and kept in
-- input.lua as one flat table; a key with one of the prefixes below goes in
-- the table of that name (touchpad_tap_to_click is input.touchpad.
-- tap_to_click). "" leaves a setting to hyprland. Guarded like defaults.lua:
-- a broken file costs the input settings and nothing else.
local okInput, input = pcall(require, "lua.input")
if okInput and type(input) == "table" then
	local nested = { "virtualkeyboard", "touchdevice", "tablettool", "touchpad", "tablet" }
	local cfg = {}
	for k, v in pairs(input) do
		if v ~= "" then
			local placed = false
			for _, n in ipairs(nested) do
				local p = n .. "_"
				if k:sub(1, #p) == p then
					cfg[n] = cfg[n] or {}
					cfg[n][k:sub(#p + 1)] = v
					placed = true
					break
				end
			end
			if not placed then cfg[k] = v end
		end
	end
	pcall(hl.config, { input = cfg })
end

-- CURSOR
hl.env("HYPRCURSOR_THEME", "XCursor-Pro-Hyprcursor-Dark")
hl.env("XCURSOR_THEME", "XCursor-Pro-Hyprcursor-Dark")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_SIZE", "24")

-- QT APPS IN THE SHELL'S COLORS: qt6ct reads the scheme quickshell's
-- ThemeSync writes (qt6ct/colors/zenworks.conf). Imported into systemd's
-- environment by autostart.lua, so the portal's screen-share picker and the
-- polkit agent get it too. Without qt6ct installed Qt ignores it.
-- quickshell inherits it and draws the same with it (morpheus/themesync.js,
-- renderQt6ct); apps it launches inherit it from it.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

hl.config({
	render = {
		expand_undersized_textures = false,
	},
	xwayland = {
		use_nearest_neighbor = false,
	},
	misc = {
		allow_session_lock_restore = true,
		-- cerberus' frost: the desktop keeps rendering under the lock and is
		-- blurred live behind it (with decoration.blur below), instead of a
		-- screenshot blurred at lock time
		session_lock_xray = true,
		session_lock_blur = true,
		disable_splash_rendering = true,
		initial_workspace_tracking = 0,
		close_special_on_empty = true,
		disable_hyprland_logo = true,
		background_color = 0x000000,
		middle_click_paste = false,
		-- screens turned off (idle, or binds.lua's screensOff) come back on
		-- any key; a mouse move too when wake.lua says so (below)
		key_press_enables_dpms = true,
		mouse_move_enables_dpms = false,
	},

	ecosystem = {
		no_donation_nag = true,
	},

	general = {
        layout = "dwindle",
		border_size = 1,
		col = {
			inactive_border = "#45505C4D",
			active_border = "#45505CCC",
		},
		gaps_out = 0,
		gaps_in = 0,
		snap = {
			enabled = true,
            border_overlap = true,
		},
	},

    scrolling = {
        column_width = 0.95,
        focus_fit_method = 0,
    },
	dwindle = {
		preserve_split = true,
	},
	decoration = {
		dim_special = 0.8,
        -- oracle's Corner rounding writes this number (morpheus/ThemeSync.qml)
        rounding = 5,
		blur = {
            passes = 2,
            special = true,
            popups = true,
            popups_ignorealpha = 0.5,
		},
		shadow = {
            range = 70,
            render_power = 2,
            offset = { 0, 10 },
            scale = 1.0,
            color = "rgba(0,0,0,0.48)",
            -- range is global (no per-window range exists); a lighter
            -- inactive shadow fades out sooner, so it reads tighter
            color_inactive = "rgba(0,0,0,0.26)",
		},
	},

	group = {
		col = {
            border_locked_inactive = "#e78284",
			border_locked_active = "#e78284",
			border_inactive = "#eebebe",
			border_active = "#eebebe",
		},
		groupbar = {
			text_color_inactive = "#dfdfdd",
			col = {
				locked_active = "#e78284",
				locked_inactive = "#20242a",
				active = "#eebebe",
				inactive = "#20242a",
			},
			text_color = "#000000",
			indicator_height = 0,
			gradients = true,
			gaps_out = 0,
			rounding = 0,
			gaps_in = 0,
			height = 24,
		},
	},

	binds = {
		hide_special_on_workspace_change = true,
		scroll_event_delay = 0,
	},
})

-- WAKE
-- wake.lua, which oracle's Display section writes ("Wake by"): "mouse"
-- wakes screens turned off, idle or by a bind, on a mouse move as well as
-- a key press. The default: only `wake = "key"` turns it off, so no file,
-- or a broken one, wakes on the mouse too (2026-10-21). Guarded like
-- defaults.lua.
local okWake, wake = pcall(require, "lua.wake")
if not (okWake and type(wake) == "table" and wake.wake == "key") then
	pcall(hl.config, { misc = { mouse_move_enables_dpms = true } })
end

-- EFFECTS
-- effects.lua, which oracle writes (Look's "Window shadows", Motion's
-- "Window animations"): `false` turns hyprland's shadows or its animations
-- off. Only false does; no file, or a broken one, keeps both. Guarded like
-- defaults.lua.
local okFx, fx = pcall(require, "lua.effects")
if okFx and type(fx) == "table" then
	pcall(hl.config, {
		decoration = { shadow = { enabled = fx.shadows ~= false } },
		animations = { enabled = fx.animations ~= false },
	})
end

-- THEME: the shell's theme, written to theme.lua by quickshell's ThemeSync
-- whenever it changes (and `hyprctl reload` after). The colours above are
-- Zenon's; an empty table — Zenon worn, or no file at all — leaves them.
-- Guarded like defaults.lua: a broken file costs the theme and nothing else.
local okTheme, theme = pcall(require, "lua.theme")
if okTheme and type(theme) == "table" and next(theme) ~= nil then
	local t = theme
	hl.config({
		general = {
			col = {
				inactive_border = t.inactive_border,
				active_border = t.active_border,
				nogroup_border = t.nogroup_border,
				nogroup_border_active = t.nogroup_border_active,
			},
		},
		group = {
			col = {
				border_locked_inactive = t.group_border_locked_inactive or t.group_border_locked,
				border_locked_active = t.group_border_locked,
				border_inactive = t.group_border_inactive or t.group_border,
				border_active = t.group_border,
			},
			groupbar = {
				text_color = t.groupbar_text,
				text_color_inactive = t.groupbar_text_inactive,
				col = {
					locked_active = t.groupbar_locked_active,
					locked_inactive = t.groupbar_inactive,
					active = t.groupbar_active,
					inactive = t.groupbar_inactive,
				},
			},
		},
	})
	-- THE STATES A WINDOW CAN BE IN, each in the theme's own color (themesync.js
	-- says which): "<focused> <unfocused>" pairs, as border_color takes them.
	-- Dynamic rules, so a window re-colors the moment it floats, maximizes or
	-- is pinned, and back. Later rules win where two match (a pinned window is
	-- floating too); a grouped window is left to the group's own colors.
	local function stateBorder(match, colors)
		if type(colors) ~= "string" or colors == "" then return end
		match.group = false
		hl.window_rule({ match = match, border_color = colors })
	end
	stateBorder({ float = true }, t.float_border)
	stateBorder({ fullscreen_state_internal = 1 }, t.zoom_border)
	stateBorder({ pin = true }, t.pin_border)
end

-- FONT: oracle's Font, weight and size, written to font.lua by quickshell's
-- ThemeSync whenever they change (and `hyprctl reload` after). Oracle is the
-- one place a font is set: nothing above names one, and with no file
-- hyprland's own defaults stand.
-- Guarded like theme.lua: a broken file costs the font and nothing else.
local okFont, font = pcall(require, "lua.font")
if okFont and type(font) == "table" and next(font) ~= nil then
	hl.config({
		misc = {
			font_family = font.family,
		},
		group = {
			groupbar = {
				font_family = font.groupbar_family,
				font_weight_inactive = font.groupbar_weight,
				font_weight_active = font.groupbar_weight_active,
				font_size = font.groupbar_size,
			},
		},
	})
end
