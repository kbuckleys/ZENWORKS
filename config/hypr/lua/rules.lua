-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- WINDOWS: the suite's own rules are data now, in windowdefaults.lua, so
-- oracle's Windows section can list them beside yours and change them like
-- any other; they are applied with yours at the end of this file.

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

-- SHIPPED + YOURS: windowdefaults.lua (the suite's own) and windows.lua,
-- which oracle's Windows section writes (Window rules). A rule of yours
-- with a `shipped` name stands in for that shipped rule; the rest of yours
-- come after the shipped ones, so where both say something about a window,
-- yours wins. hyprland matches the WHOLE class as a regex, so the class is
-- escaped and matched as written; a title matches anywhere in the title.
-- Guarded like defaults.lua: a broken file, or a broken rule, costs only
-- itself.
local function esc(s) return (tostring(s):gsub("[%.%^%$%*%+%?%(%)%[%]%{%}%|\\]", "\\%0")) end
local function apply(r)
	if type(r) ~= "table" or r.on == false or type(r.class) ~= "string" or r.class == "" then return end
	-- a class an app makes new at every launch (transmission-gtk's
	-- "…_<pid>_<random>") is matched with any such tail, not just the
	-- one it had when the rule was picked
	local cls = r.class:gsub("_%d+_%d+$", "")
	local spec = { match = { class = esc(cls) .. "(_\\d+_\\d+)?" } }
	if type(r.title) == "string" and r.title ~= "" then spec.match.title = ".*" .. esc(r.title) .. ".*" end
	if r.float then
		spec.float = true
		if type(r.size) == "string" and r.size:match("^%d+ %d+$") then spec.size = r.size end
		if r.pin then spec.pin = true end
		if r.persistent_size then spec.persistent_size = true end
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
end
local okDef, shipped = pcall(require, "lua.windowdefaults")
if not okDef or type(shipped) ~= "table" then shipped = {} end
local okWin, yours = pcall(require, "lua.windows")
if not okWin or type(yours) ~= "table" then yours = {} end
local replaced = {}
for _, r in ipairs(yours) do
	if type(r) == "table" and type(r.shipped) == "string" and r.shipped ~= "" then replaced[r.shipped] = true end
end
for _, r in ipairs(shipped) do
	if type(r) == "table" and not replaced[r.shipped] then pcall(apply, r) end
end
for _, r in ipairs(yours) do pcall(apply, r) end
