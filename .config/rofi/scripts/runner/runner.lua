#!/usr/bin/lua

-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

local HOME = os.getenv("HOME")
local DIR = HOME .. "/.config/rofi/scripts/runner"
local SHELL = os.getenv("SHELL") or "/bin/bash"
local CONFIG = DIR .. "/config.rasi"
local DRUN_THEME = DIR .. "/drun.rasi"
local RUNNER_THEME = DIR .. "/runner.rasi"
local MODE_THEME = DIR .. "/runnerok.rasi"

local HIST = HOME .. "/.cache/rofi-run-history"
local HIST_MAX = 100

local ICON_T = string.char(0xEE, 0xAA, 0x85)
local ICON_P = string.char(0xF3, 0xB0, 0x98, 0x94)
local ICON_B = string.char(0xEE, 0xB8, 0xA3)

local function shell_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function starts_with(s, prefix)
    return s:sub(1, #prefix) == prefix
end

local function strip_prefix(s)
    local _, pos = s:find("  ", 1, true)
    if pos then return s:sub(pos + 1) end
    return s
end

if os.getenv("ROFI_SOCKET") then
    local parts = { "'--from-rofi'" }
    for i = 1, #arg do
        if arg[i] then parts[#parts + 1] = shell_quote(arg[i]) end
    end
    local script = arg[0] or debug.getinfo(1, "S").source:match("^@(.+)$")
    os.execute("env -u ROFI_SOCKET lua " .. shell_quote(script) .. " " .. table.concat(parts, " "))
    os.exit(0)
end

local function rofi_dmenu(entries, theme, prompt, extra_args)
    local entry_tf = os.tmpname()
    local f = io.open(entry_tf, "w")
    if not f then os.remove(entry_tf); return nil, -1 end
    for _, e in ipairs(entries) do f:write(e, "\n") end
    f:close()

    local out_tf = os.tmpname()
    local extra = extra_args or ""
    local cmd = string.format(
        "rofi -dmenu -no-auto-select -config %s -theme %s -p %s -i %s < %s > %s 2>/dev/null; printf '\\n__EXIT__%%d__' $? >> %s",
        shell_quote(CONFIG), shell_quote(theme), shell_quote(prompt), extra,
        shell_quote(entry_tf), shell_quote(out_tf), shell_quote(out_tf))
    os.execute(cmd)

    local raw = read_file(out_tf)
    os.remove(entry_tf)
    os.remove(out_tf)

    local exit_code = tonumber((raw or ""):match("__EXIT__(%d+)__")) or 0
    local result = trim((raw or ""):match("^(.-)\n__EXIT__%d+__") or "")
    if result == "" then return nil, exit_code end
    return result, exit_code
end

local function read_history()
    local f = io.open(HIST, "r")
    if not f then return {} end
    local lines = {}
    for line in f:lines() do
        if line ~= "" then
            local rest = line
            for _, icon in ipairs({ ICON_T, ICON_P, ICON_B }) do
                if rest:sub(1, #icon) == icon then
                    rest = rest:sub(#icon + 1)
                    break
                end
            end
            if not rest:match("^%s*$") then
                lines[#lines + 1] = line
            end
        end
    end
    f:close()
    return lines
end

local function add_history(entry, mode)
    local hist = read_history()
    local tag = mode == "Terminal" and ICON_T or ICON_P
    local formatted = tag .. "  " .. entry
    local filtered = {}
    for _, e in ipairs(hist) do
        if e ~= formatted then filtered[#filtered + 1] = e end
    end
    table.insert(filtered, 1, formatted)
    while #filtered > HIST_MAX do table.remove(filtered) end
    local f = io.open(HIST, "w")
    if not f then return end
    for _, e in ipairs(filtered) do f:write(e .. "\n") end
    f:close()
end

local function delete_from_history(entry)
    local hist = read_history()
    local filtered = {}
    for _, e in ipairs(hist) do
        if e ~= entry then filtered[#filtered + 1] = e end
    end
    local f = io.open(HIST, "w")
    if not f then return end
    for _, e in ipairs(filtered) do f:write(e .. "\n") end
    f:close()
end

local function parse_desktop(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local name, exec, nodisplay = nil, nil, false
    for line in f:lines() do
        if line:match("^Name=") then name = line:match("^Name=(.+)$")
        elseif line:match("^Exec=") then exec = line:match("^Exec=(.+)$")
        elseif line:match("^NoDisplay=true") then nodisplay = true end
    end
    f:close()
    if nodisplay or not name or not exec then return nil end
    exec = exec:gsub("%%[fFuUdDnNickvm]", ""):gsub("%s+$", "")
    return { name = name, exec = exec, desktop = path:match("([^/]+)%.desktop$") }
end

local cached_apps = nil

local function get_apps()
    if cached_apps then return cached_apps end
    local apps, seen = {}, {}
    for _, dir in ipairs({ "/usr/share/applications", HOME .. "/.local/share/applications" }) do
        local p = io.popen("ls " .. shell_quote(dir) .. "/*.desktop 2>/dev/null")
        if p then
            for file in p:lines() do
                local app = parse_desktop(file)
                if app and not seen[app.name:lower()] then
                    seen[app.name:lower()] = true
                    apps[#apps + 1] = app
                end
            end
            p:close()
        end
    end
    table.sort(apps, function(a, b) return a.name:lower() < b.name:lower() end)
    cached_apps = apps
    return apps
end

local function find_app(name)
    for _, app in ipairs(get_apps()) do
        if app.name == name then return app end
    end
    return nil
end

local function run_terminal(cmd)
    add_history(cmd, "Terminal")
    os.execute(string.format(
        "setsid kitty -1 --detach --hold --title runner %s -i -c %s >/dev/null 2>&1",
        SHELL, shell_quote(cmd)))
end

local function run_process(cmd)
    add_history(cmd, "Process")
    os.execute(string.format(
        "setsid %s -i -c %s >/dev/null 2>&1 &",
        SHELL, shell_quote(cmd)))
end

local function mode_picker(cmd)
    local term_label = ICON_T .. "  Terminal"
    local process_label = ICON_P .. "  Process"
    local back_label = ICON_B .. "  Back"
    local result = rofi_dmenu(
        { term_label, process_label, back_label },
        MODE_THEME,
        "",
        "-selected-row 0 -mesg " .. shell_quote(cmd))
    if not result then return "Back" end
    return strip_prefix(result)
end

local function run_drun()
    local apps = get_apps()
    local entries = {}
    for _, app in ipairs(apps) do entries[#entries + 1] = app.name end
    local result, code = rofi_dmenu(entries, DRUN_THEME, "Launch",
        "-kb-custom-1 'Alt+c'")
    if code == 10 then return false end
    if result then
        local app = find_app(result)
        if app then
            os.execute(string.format("gtk-launch %s >/dev/null 2>&1 &", shell_quote(app.desktop)))
        end
    end
    return true
end

local function run_runner()
    local runner_args = "-kb-custom-1 'Alt+c' -kb-custom-2 'Alt+Delete' -kb-accept-custom 'Alt+Return'"
    while true do
        local entries = read_history()
        if #entries == 0 then
            entries[1] = "(empty history)"
        end
        local raw, code = rofi_dmenu(entries, RUNNER_THEME, "Run", runner_args)

        if code == 10 then
            return false
        end

        if code == 11 then
            if raw and raw ~= "(empty history)" then delete_from_history(raw) end
            goto continue
        end

        if not raw or raw == "" or raw == "(empty history)" then
            return true
        end

        if raw:sub(1, #ICON_T) == ICON_T then
            run_terminal(strip_prefix(raw))
            return true
        elseif raw:sub(1, #ICON_P) == ICON_P then
            run_process(strip_prefix(raw))
            return true
        end

        local action = mode_picker(raw)
        if action == "Terminal" then
            run_terminal(raw)
            return true
        elseif action == "Process" then
            run_process(raw)
            return true
        end

        ::continue::
    end
end

local mode = arg[1] or "drun"
while true do
    if mode == "drun" then
        local done = run_drun()
        if done then break end
        mode = "runner"
    else
        local done = run_runner()
        if done then break end
        mode = "drun"
    end
end
os.exit(0)
