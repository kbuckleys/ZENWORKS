#!/usr/bin/env lua

-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- Resolve our own directory so the tree can live anywhere.
local DIR = (arg[0] or debug.getinfo(1, "S").source:match("^@(.+)$") or ""):match("^(.*)/") or "."
if DIR == "." then DIR = os.getenv("PWD") or "."
elseif DIR:sub(1, 1) ~= "/" then DIR = (os.getenv("PWD") or ".") .. "/" .. DIR end

local THEME = DIR .. "/hitman.rasi"
local CONFIRM_THEME = DIR .. "/hitmanok.rasi"

local function rofi(input, args)
    local escaped = input:gsub("'", "'\\''")
    local cmd = string.format("printf '%s' | rofi %s", escaped, args)
    local handle = io.popen(cmd)
    if not handle then return nil end
    local out = handle:read("*a")
    handle:close()
    return out and out:gsub("\n$", "") or nil
end

local function show_error(msg)
    local escaped = msg:gsub("'", "'\\''")
    os.execute(string.format(
        "rofi -e '%s' -theme '%s'",
        escaped, CONFIRM_THEME))
end

local function main()
    local ps_handle = io.popen("ps -eo pid=,user=,args= --sort=pid")
    if not ps_handle then
        show_error("Failed to list processes")
        os.exit(1)
    end

    local lines = {}
    for line in ps_handle:lines() do
        local pid, user, rest = line:match("^%s*(%S+)%s+(%S+)%s+(.*)$")
        if pid and user and rest then
            lines[#lines + 1] = string.format("%-6s %-8s %s", pid, user, rest)
        end
    end
    ps_handle:close()

    if #lines == 0 then
        show_error("No processes found")
        os.exit(1)
    end
    local formatted = table.concat(lines, "\n") .. "\n"

    local uptime_handle = io.popen("uptime -p")
    local uptime_str = uptime_handle and uptime_handle:read("*a"):gsub("^up ", ""):gsub("\n$", "") or "unknown uptime"
    if uptime_handle then uptime_handle:close() end

    local mesg = string.format("%d Processes ~ Uptime: %s\nshift + return: multi-select  \u{F01D9}  return: confirm", #lines, uptime_str)

    local selection = rofi(formatted, string.format(
        "-dmenu -multi-select -i -markup-rows -ballot-selected-str '<span foreground=\"#e78284\">\u{F09FC}</span> ' -ballot-unselected-str '' -p 'Kill Process' -mesg '%s' -theme '%s'",
        mesg, THEME))

    if not selection or selection == "" then
        os.exit(0)
    end

    local pids = {}
    for line in selection:gmatch("[^\n]+") do
        local pid = line:match("^(%d+)")
        if pid then
            pids[#pids + 1] = pid
        end
    end

    if #pids == 0 then
        os.exit(1)
    end

    local confirm_msg
    if #pids == 1 then
        local sel_line = selection:match("^[^\n]+")
        local cmd = sel_line and sel_line:match("^%d+%s+%S+%s+(.+)") or nil
        confirm_msg = cmd and ("Kill " .. cmd) or "Kill Process"
    else
        confirm_msg = string.format("Kill %d Processes", #pids)
    end
    local confirm = rofi(confirm_msg .. "\nABORT", string.format(
        "-dmenu -p 'Confirm' -mesg '%s' -selected-row 0 -theme '%s'",
        confirm_msg, CONFIRM_THEME))

    if confirm ~= confirm_msg then
        return
    end

    local failed = {}
    for _, pid in ipairs(pids) do
        local ret = os.execute(string.format("kill %s 2>/dev/null", pid))
        local success = (ret == true) or (ret == 0)
        if not success then
            failed[#failed + 1] = pid
        end
    end

    if #failed == 0 then
        os.exit(0)
    else
        show_error(string.format("Failed to kill PID(s): %s", table.concat(failed, ", ")))
        os.exit(1)
    end
end

while true do
    main()
end
