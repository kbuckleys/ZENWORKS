-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

hl.window_rule({ match = { class = "kitty" },                                       float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "ceres" },             float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "delphi" },            float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "oracle" },            float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "calypso" },           float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "terminus" },          float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "alexandria" },        float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "clio" },              float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "hermes" },            float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "argus" },             float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "minerva" },           float = true })  -- keeps its own size, less its sidebar (MinervaWindow keepSize)
hl.window_rule({ match = { class = "org.quickshell", title = "hestia" },            float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "kairos" },            float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "hygieia" },           float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "picasso-view" },      float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "plato-capture" },     float = true, persistent_size = true })
hl.window_rule({ match = { class = "org.quickshell", title = "terminus-picker" },   float = true, persistent_size = true })
hl.window_rule({ match = { class = "steam", title = "Steam Settings" },             float = true, persistent_size = true })
hl.window_rule({ match = { class = "net.davidotek.pupgui2" },                       float = true })
hl.window_rule({ match = { class = "mpv" },                                         float = true })

-- GLOBAL BLUR
-- blur_popups: a layer's own popups (metis' bubble, the bar's cards) are
-- frosted too — decoration.blur.popups only reaches a window's popups
hl.layer_rule({ match = { namespace = ".*" }, blur = true, blur_popups = true, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "morpheus-bar(-clear)?" }, animation = "none" })
-- menus that are layer surfaces (morpheus/CardMenu: icarus, the tray, the bell)
-- animate themselves, as the popup menus do; hyprland's layer animation on top
-- made them move differently
hl.layer_rule({ match = { namespace = "morpheus-menu" }, animation = "none" })
-- the pill with oracle's Blur behind off: after the global rule, so it wins
hl.layer_rule({ match = { namespace = "morpheus-bar-clear" }, blur = false })
-- cerberus' black veil, faded in before the lock and out after it: no map
-- animation to fight its own fade, and no blur to pop in at half alpha
hl.layer_rule({ match = { namespace = "cerberus-veil" }, animation = "none", blur = false })

-- SPECIAL WORKSPACE
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })

-- YOURS: windows.lua, which oracle's Windows section writes (Window rules).
-- After the suite's own, so where both say something about a window, yours
-- wins. hyprland matches the WHOLE class as a regex, so the class is
-- escaped and matched as written; a title matches anywhere in the title.
-- Guarded like defaults.lua: a broken file, or a broken rule, costs only
-- itself.
local okWin, yours = pcall(require, "lua.windows")
if okWin and type(yours) == "table" then
	local function esc(s) return (tostring(s):gsub("[%.%^%$%*%+%?%(%)%[%]%{%}%|\\]", "\\%0")) end
	for _, r in ipairs(yours) do
		pcall(function()
			if type(r) ~= "table" or r.on == false or type(r.class) ~= "string" or r.class == "" then return end
			local spec = { match = { class = esc(r.class) } }
			if type(r.title) == "string" and r.title ~= "" then spec.match.title = ".*" .. esc(r.title) .. ".*" end
			if r.float then
				spec.float = true
				if type(r.size) == "string" and r.size:match("^%d+ %d+$") then spec.size = r.size end
				if r.pin then spec.pin = true end
			end
			if r.center then spec.center = true end
			if type(r.workspace) == "string" and r.workspace ~= "" then
				spec.workspace = r.workspace .. (r.silent and " silent" or "")
			end
			if type(r.opacity) == "number" and r.opacity >= 10 and r.opacity < 100 then
				spec.opacity = tostring(r.opacity / 100)
			end
			if r.no_blur then spec.no_blur = true end
			if type(r.idle_inhibit) == "string" and r.idle_inhibit ~= "" then spec.idle_inhibit = r.idle_inhibit end
			if r.open == "maximize" then spec.maximize = true end
			if r.open == "fullscreen" then spec.fullscreen = true end
			if r.no_initial_focus then spec.no_initial_focus = true end
			hl.window_rule(spec)
		end)
	end
end
