-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

require("lua.wf-recorder")
require("lua.smart-move")
require("lua.animations")
require("lua.autostart")
require("lua.hyprshot")
require("lua.layout")
require("lua.binds")
require("lua.rules")
require("lua.base")
require("lua.zoom")

-- This machine's own settings, last so they override the above: monitors,
-- cursor, GPU tuning, personal binds. Optional and not committed — copy
-- lua/machine.example.lua to lua/machine.lua. A missing file is fine; an
-- error INSIDE it is still reported rather than swallowed.
local ok, err = pcall(require, "lua.machine")
if not ok and not tostring(err):find("module 'lua.machine' not found", 1, true) then
	error(err, 0)
end
