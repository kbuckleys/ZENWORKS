-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- ARGUS: the screen recorder lives with the shell, in quickshell/argus/
-- argus.lua, and defines ZenRecord for binds.lua and the bar. Guarded: if
-- it is missing, recording goes and nothing else does.
local xdg = os.getenv("XDG_CONFIG_HOME")
local shell = ((xdg and xdg ~= "") and xdg or (os.getenv("HOME") .. "/.config")) .. "/quickshell"
package.path = shell .. "/?.lua;" .. package.path
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
