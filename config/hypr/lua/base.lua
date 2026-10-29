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
local platoBin = ZENWORKS.shell .. "/plato/bin"
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
-- the click that focuses a window only focuses it, the way macOS does: it
-- is not also a press on whatever is under the pointer (0.57). Not a
-- setting: the old click-through is gone on purpose.
hl.config({ input = { swallow_focus_click = true } })

-- CURSOR
hl.env("HYPRCURSOR_THEME", "XCursor-Pro-Hyprcursor-Dark")
-- X apps (Spotify, Steam, anything under XWayland) cannot read hyprcursor:
-- theirs is the same design in X's own format (xcursor-pro-cursor-theme;
-- user, 2026-10-28: "my cursors are different in apps like spotify and
-- steam"). scripts/gtkscheme.sh tells GTK and ~/.icons/default the same.
hl.env("XCURSOR_THEME", "XCursor-Pro-Dark")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_SIZE", "24")

-- QT APPS IN THE SHELL'S COLORS: qt6ct reads the scheme quickshell's
-- ThemeSync writes (qt6ct/colors/zenworks.conf). Imported into systemd's
-- environment by autostart.lua, so the portal's screen-share picker and the
-- polkit agent get it too. Without qt6ct installed Qt ignores it.
-- quickshell inherits it and draws the same with it (morpheus/themesync.js,
-- renderQt6ct); apps it launches inherit it from it.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- KITTY reads its config from ~/.config/zenworks/kitty, which the shell
-- writes (morpheus/themesync.js renderKittyConf): the shipped kitty.conf
-- beside this config, the shell's font and theme, then your custom.conf.
hl.env("KITTY_CONFIG_DIRECTORY", ZENWORKS.kitty)

-- INPUT METHODS: fcitx5, when oracle's Input methods is on (inputmethod.lua)
-- and fcitx5 is installed; autostart.lua starts it. Qt apps try the Wayland
-- text-input protocol first and fcitx5's own module after; apps under
-- XWayland find it through XMODIFIERS. GTK and kitty need nothing.
-- NEVER GTK_IM_MODULE or QT_IM_MODULE: on Wayland they push apps off
-- text-input (oracle/tests/inputmethod.js). Guarded like defaults.lua.
local okIm, im = pcall(require, "lua.inputmethod")
local fcitx = io.open("/usr/bin/fcitx5", "r")
if fcitx then fcitx:close() end
ZENWORKS.inputMethod = okIm and type(im) == "table" and im.on == true and fcitx ~= nil
if ZENWORKS.inputMethod then
	hl.env("QT_IM_MODULES", "wayland;fcitx")
	hl.env("XMODIFIERS", "@im=fcitx")
end

-- THE DESKTOP'S NAME, as `zen` exports it — set again here in case
-- Hyprland put its own over it as it started: xdg-desktop-portal picks
-- zenworks-portals.conf by it, and autostart.lua's import hands it on.
hl.env("XDG_CURRENT_DESKTOP", "ZENWORKS:Hyprland")

-- SSH AGENT: one for the session, so a key's passphrase is asked once per
-- login (delphi's SSH keys page writes AddKeysToAgent into ~/.ssh/config).
-- autostart.lua starts it at this socket. Left alone when something else
-- already runs an agent (gnome-keyring, gpg-agent): SSH_AUTH_SOCK is set then.
local runtime = os.getenv("XDG_RUNTIME_DIR")
if runtime and (os.getenv("SSH_AUTH_SOCK") or "") == "" then
	hl.env("SSH_AUTH_SOCK", runtime .. "/ssh-agent.socket")
end

-- CORNER: oracle's Corner rounding for windows, written to corner.lua by
-- quickshell's ThemeSync (and `hyprctl reload` after); 5 with no file yet.
local okCorner, cornerFile = pcall(require, "lua.corner")
local corner = okCorner and type(cornerFile) == "table" and tonumber(cornerFile.rounding) or 5

-- FROST: oracle's Frost style, Hyprland 0.57's blur variant, and acrylic's
-- tint (the accent), written to frost.lua by ThemeSync; plain kawase with
-- no file yet. The moving ones (ripple … fluid_jar) are oracle's to offer
-- with a warning; anything Hyprland does not have stays kawase.
local okFrost, frostFile = pcall(require, "lua.frost")
local frost = { variant = "kawase" }
if okFrost and type(frostFile) == "table" then
	local known = { kawase = true, frost = true, acrylic = true, haze = true, prism = true, ripple = true,
		water = true, drops = true, aurora = true, heat_shimmer = true, fluid_jar = true }
	if known[frostFile.variant] then frost.variant = frostFile.variant end
	for _, k in ipairs({ "tint", "aurora1", "aurora2", "fluid" }) do
		if type(frostFile[k]) == "string" then frost[k] = frostFile[k] end
	end
end

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
		-- a terminal's BEL: howler plays it (and keeps quiet when toasts do)
		bell_sound = "none",
		disable_hyprland_logo = true,
		-- XDG_CURRENT_DESKTOP is ZENWORKS:Hyprland on purpose (bin/zen,
		-- and above): without this Hyprland greets every login with "set
		-- externally … might cause issues" (user, 2026-10-25)
		disable_xdg_env_checks = true,
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
		-- 8 outside, 2 between (2026-10-25); oracle's Windows section moves
		-- them, through effects.lua (below)
		gaps_out = 8,
		gaps_in = 2,
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
        -- oracle's Corner rounding (lua/corner.lua, above)
        rounding = corner,
		blur = {
            passes = 2,
            special = true,
            popups = true,
            popups_ignorealpha = 0.5,
            -- oracle's Frost style (lua/frost.lua, above)
            variant = frost.variant,
            acrylic = frost.tint and { tint = frost.tint } or nil,
            aurora = frost.aurora1 and { color1 = frost.aurora1, color2 = frost.aurora2 } or nil,
            fluid_jar = frost.fluid and { color = frost.fluid } or nil,
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
		-- a tiled window dragged loose floats centered under the pointer,
		-- not left hanging off it at its tiled offset (0.57's default, kept
		-- on purpose and written down so a later default cannot move it)
		drag_center_window = true,
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
-- "Window animations", and the window rows under Windows): `false` turns
-- hyprland's shadows or its animations off; the gaps, border, layout,
-- edge resizing, dim and unfocused opacity are laid over the ones above.
-- A field the file lacks, or has as the wrong kind, keeps what is above.
-- Each is its own call, so one hyprland refuses costs only that one.
-- Guarded like defaults.lua.
local okFx, fx = pcall(require, "lua.effects")
if okFx and type(fx) == "table" then
	pcall(hl.config, {
		decoration = {
			shadow = { enabled = fx.shadows ~= false },
			-- Motion's Wobbly windows: off unless the file says true
			wobble = { enabled = fx.wobble == true },
		},
		animations = { enabled = fx.animations ~= false },
	})
	local function num(v) return type(v) == "number" and v or nil end
	if num(fx.gaps_out) then pcall(hl.config, { general = { gaps_out = fx.gaps_out } }) end
	if num(fx.gaps_in) then pcall(hl.config, { general = { gaps_in = fx.gaps_in } }) end
	if num(fx.border_size) then pcall(hl.config, { general = { border_size = fx.border_size } }) end
	if fx.layout == "dwindle" or fx.layout == "master" or fx.layout == "scrolling" then
		pcall(hl.config, { general = { layout = fx.layout } })
	end
	if type(fx.resize_on_border) == "boolean" then
		pcall(hl.config, { general = { resize_on_border = fx.resize_on_border } })
	end
	if num(fx.dim_inactive) then
		pcall(hl.config, { decoration = { dim_inactive = fx.dim_inactive > 0, dim_strength = fx.dim_inactive } })
	end
	if num(fx.inactive_opacity) then
		pcall(hl.config, { decoration = { inactive_opacity = fx.inactive_opacity } })
	end
end

-- HYPRLAND: the rest of hyprland's settings, written by oracle (Windows,
-- Tiling, Workspaces, Window effects, Motion, Keyboard & mouse, Display)
-- to hyprland.lua as `["decoration:blur:size"] = 8`, hyprland's own names.
-- Laid over everything above, one call each, so a value hyprland refuses
-- costs that one. "" leaves a setting to hyprland; "0 10" is a pair.
-- zen:gesture:<fingers>:<direction> = "<action>" is a touchpad gesture, and
-- zen:ws:<n>:monitor / :layout a workspace's rule. Guarded like defaults.lua.
local okHl, hlFile = pcall(require, "lua.hyprland")
if okHl and type(hlFile) == "table" then
	local spaces = {}
	for k, v in pairs(hlFile) do
		if type(k) == "string" and v ~= "" then
			local fingers, dir = k:match("^zen:gesture:(%d):(%a+)$")
			local ws, field = k:match("^zen:ws:(%d+):(%a+)$")
			if fingers and type(v) == "string" then
				local g = { fingers = tonumber(fingers), direction = dir, action = v }
				if v == "special" then g.workspace_name = "special" end
				pcall(hl.gesture, g)
			elseif ws then
				spaces[ws] = spaces[ws] or {}
				spaces[ws][field] = v
			elseif not k:find("^zen:") then
				if type(v) == "string" then
					local a, b = v:match("^%s*(-?[%d.]+)%s+(-?[%d.]+)%s*$")
					if a then v = { tonumber(a), tonumber(b) } end
				end
				local cfg = {}
				local node = cfg
				local path = {}
				for p in k:gmatch("[^:]+") do path[#path + 1] = p end
				for i = 1, #path - 1 do
					node[path[i]] = {}
					node = node[path[i]]
				end
				node[path[#path]] = v
				pcall(hl.config, cfg)
			end
		end
	end
	for ws, r in pairs(spaces) do
		local rule = { workspace = ws }
		if type(r.monitor) == "string" then rule.monitor = r.monitor end
		if r.layout == "dwindle" or r.layout == "master" or r.layout == "scrolling" then rule.layout = r.layout end
		pcall(hl.workspace_rule, rule)
	end
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
	-- a window rule's Border (rules.lua queues them in ZENWORKS.ruleBorders):
	-- the theme's rule_<hue> pair, after the states so the one chosen wins
	for _, b in ipairs(ZENWORKS.ruleBorders or {}) do
		local match = { group = false }
		for k, v in pairs(b.match) do match[k] = v end
		pcall(stateBorder, match, t["rule_" .. b.hue])
	end
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
