-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- ENV
-- Nvidia cache limit set to 20 GB
hl.env("__GL_SHADER_DISK_CACHE_SIZE", "21474836480")
hl.env("__GL_SHADER_DISK_CACHE_SKIP_CLEANUP", "1")
hl.env("QSG_RENDER_LOOP", "threaded")

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

hl.config({
	render = {
		expand_undersized_textures = false,
	},
	xwayland = {
		use_nearest_neighbor = false,
	},
	misc = {
        font_family = "JetBrainsMono Nerd Font Medium",
		allow_session_lock_restore = true,
		disable_splash_rendering = true,
		initial_workspace_tracking = 0,
		close_special_on_empty = true,
		disable_hyprland_logo = true,
		background_color = 0x000000,
		middle_click_paste = false,
	},

	ecosystem = {
		no_donation_nag = true,
	},

	general = {
        layout = "scrolling",
		border_size = 1,
		col = {
			inactive_border = "#45505C4D",
			active_border = "#45505CCC",
		},
		gaps_out = 2,
		gaps_in = -2,
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
			font_family = "JetBrainsMono Nerd Font Propo",
			text_color = "#000000",
			font_weight_active = "bold",
			indicator_height = 0,
			gradients = true,
			font_size = 14,
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
			},
		},
		group = {
			col = {
				border_locked_inactive = t.group_border_locked,
				border_locked_active = t.group_border_locked,
				border_inactive = t.group_border,
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
end
