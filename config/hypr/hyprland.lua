-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- WHERE EVERYTHING IS. This config ships beside the shell — /usr/share/
-- zenworks/{hypr,quickshell} from the package, or a working copy's, started
-- by `zen` (Hyprland --config this file) — and is only read. What you
-- change lives in ~/.config/zenworks/hypr: oracle's settings (monitors.lua,
-- keys.lua, input.lua …) and the files the shell generates (theme.lua,
-- font.lua, corner.lua, filter.lua, the filter shaders). A file there is
-- required INSTEAD of the shipped one of the same name; until oracle writes
-- one, the shipped stock stands. ZENWORKS is how the other files find them.
local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]+$") or "."
local xdg = os.getenv("XDG_CONFIG_HOME")
local config = (xdg and xdg ~= "") and xdg or (os.getenv("HOME") .. "/.config")
local qs = (os.getenv("QS_CONFIG_PATH") or ""):gsub("/shell%.qml$", ""):gsub("/+$", "")
ZENWORKS = {
	hypr = here,
	user = config .. "/zenworks/hypr",
	-- the shell: where the launcher said (QS_CONFIG_PATH), else beside this
	shell = qs ~= "" and qs or ((here:match("^(.*)/[^/]+$") or ".") .. "/quickshell"),
	-- kitty's config: the one the shell writes, including the shipped one
	kitty = config .. "/zenworks/kitty",
}
package.path = ZENWORKS.user .. "/?.lua;" .. here .. "/?.lua;" .. ZENWORKS.shell .. "/?.lua;" .. package.path

-- ARGUS: the screen recorder lives with the shell, in quickshell/argus/
-- argus.lua, and defines ZenRecord for binds.lua and the bar. Guarded: if
-- it is missing, recording goes and nothing else does.
pcall(require, "argus.argus")

require("lua.smart-move")
require("lua.animations")
require("lua.autostart")
require("lua.layout")
require("lua.binds")
require("lua.rules")
require("lua.monitors")
require("lua.base")
require("lua.zoom")
