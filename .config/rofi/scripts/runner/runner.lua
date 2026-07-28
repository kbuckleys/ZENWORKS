#!/usr/bin/lua

-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

local HOME = os.getenv("HOME")
local DIR = HOME .. "/.config/rofi/scripts/runner"
local SHELL = os.getenv("SHELL") or "/bin/bash"
local CONFIG = DIR .. "/config.rasi"
local RUNNER_THEME = DIR .. "/runner.rasi"
local MODE_THEME = DIR .. "/runnerok.rasi"
local HIST = HOME .. "/.cache/rofi-run-history"
local HIST_MAX = 200
local FREQ = HOME .. "/.cache/rofi-run-freq"

local ICON_T = string.char(0xEE, 0xAA, 0x85)
local ICON_P = string.char(0xF3, 0xB0, 0x98, 0x94)

local function shell_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
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

local function strip_hidden(s)
    local pos = s:find("<span", 1, true)
    if pos then return s:sub(1, pos - 1) end
    return s
end

if os.getenv("ROFI_SOCKET") then
    local parts = {}
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
    local cmd = string.format(
        "rofi -dmenu -no-auto-select -config %s -theme %s -p %s -i %s < %s > %s 2>/dev/null; printf '\\n__EXIT__%%d__' $? >> %s",
        shell_quote(CONFIG), shell_quote(theme), shell_quote(prompt),
        extra_args or "", shell_quote(entry_tf), shell_quote(out_tf), shell_quote(out_tf))
    os.execute(cmd)

    local raw = nil
    local rf = io.open(out_tf, "r")
    if rf then raw = rf:read("*a"); rf:close() end
    os.remove(entry_tf)
    os.remove(out_tf)

    local exit_code = tonumber((raw or ""):match("__EXIT__(%d+)__")) or 0
    local result = trim((raw or ""):match("^(.-)\n__EXIT__%d+__") or "")
    if result == "" then return nil, exit_code end
    return result, exit_code
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

local function read_history()
    local f = io.open(HIST, "r")
    if not f then return {} end
    local lines = {}
    for line in f:lines() do
        if line ~= "" then
            local rest = line
            for _, icon in ipairs({ ICON_T, ICON_P }) do
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

local function write_history(lines)
    local f = io.open(HIST, "w")
    if not f then return end
    for _, e in ipairs(lines) do f:write(e, "\n") end
    f:close()
end

local function read_freq()
    local data = {}
    local f = io.open(FREQ, "r")
    if not f then return data end
    for line in f:lines() do
        local name, count = line:match("^(.-)=(%d+)$")
        if name and name ~= "" then data[name] = tonumber(count) end
    end
    f:close()
    return data
end

local function write_freq(data)
    local f = io.open(FREQ, "w")
    if not f then return end
    for name, count in pairs(data) do
        f:write(name, "=", tostring(count), "\n")
    end
    f:close()
end

local function bump_freq(name)
    if not name or name == "" then return end
    local data = read_freq()
    data[name] = (data[name] or 0) + 1
    write_freq(data)
end

local function add_history(entry, mode)
    local hist = read_history()
    local formatted = (mode == "Terminal" and ICON_T or ICON_P) .. "  " .. entry
    local filtered = {}
    for _, e in ipairs(hist) do
        if e ~= formatted then filtered[#filtered + 1] = e end
    end
    table.insert(filtered, 1, formatted)
    if #filtered > HIST_MAX then
        for i = HIST_MAX + 1, #filtered do filtered[i] = nil end
    end
    write_history(filtered)
end

local function delete_from_history(entry)
    local hist = read_history()
    local filtered = {}
    for _, e in ipairs(hist) do
        if e ~= entry then filtered[#filtered + 1] = e end
    end
    write_history(filtered)
end

local function get_combined_entries()
    local apps = get_apps()
    local hist = read_history()
    local freq = read_freq()

    local app_names = {}
    for _, app in ipairs(apps) do
        app_names[app.name:lower()] = true
    end

    local filtered_hist = {}
    for _, entry in ipairs(hist) do
        local cmd = strip_prefix(entry)
        if not app_names[cmd:lower()] then
            filtered_hist[#filtered_hist + 1] = entry
        end
    end

    local entries = {}
    for _, app in ipairs(apps) do
        entries[#entries + 1] = app.name .. '<span size="1">  ' .. app.exec .. '</span>'
    end
    for _, entry in ipairs(filtered_hist) do
        entries[#entries + 1] = entry
    end

    table.sort(entries, function(a, b)
        local key_a = a:find("<span", 1, true) and strip_hidden(a) or strip_prefix(a)
        local key_b = b:find("<span", 1, true) and strip_hidden(b) or strip_prefix(b)
        local count_a = freq[key_a] or 0
        local count_b = freq[key_b] or 0
        if count_a ~= count_b then return count_a > count_b end
        return a < b
    end)

    return entries
end

local function run_terminal(cmd)
    add_history(cmd, "Terminal")
    bump_freq(cmd)
    os.execute(string.format(
        "setsid kitty -1 --detach --hold --title runner %s -i -c %s >/dev/null 2>&1",
        SHELL, shell_quote(cmd)))
end

local function run_process(cmd)
    add_history(cmd, "Process")
    bump_freq(cmd)
    os.execute(string.format(
        "setsid %s -i -c %s >/dev/null 2>&1 &",
        SHELL, shell_quote(cmd)))
end

local function mode_picker(cmd)
    local result = rofi_dmenu({
        ICON_T .. "  Terminal",
        ICON_P .. "  Process",
        string.char(0xEE, 0xB8, 0xA3) .. "  Back",
    }, MODE_THEME, "", "-selected-row 0 -mesg " .. shell_quote(cmd))
    if not result then return "Back" end
    return strip_prefix(result)
end

local function run()
    local runner_args = "-markup-rows -kb-custom-1 'Alt+Delete' -kb-accept-custom 'Alt+Return'"
    while true do
        local entries = get_combined_entries()
        if #entries == 0 then break end
        local raw, code = rofi_dmenu(entries, RUNNER_THEME, "Run", runner_args)

        if code == 10 then
            if raw and (starts_with(raw, ICON_T) or starts_with(raw, ICON_P)) then
                delete_from_history(raw)
            end
            goto continue
        end

        if not raw or raw == "" then break end

        local display = raw:find("<span", 1, true) and strip_hidden(raw) or strip_prefix(raw)
        local app = find_app(display)

        if app then
            bump_freq(display)
            os.execute(string.format("gtk-launch %s >/dev/null 2>&1 &", shell_quote(app.desktop)))
            break
        elseif starts_with(raw, ICON_T) then
            run_terminal(display)
            break
        elseif starts_with(raw, ICON_P) then
            run_process(display)
            break
        end

        local action = mode_picker(display)
        if action == "Terminal" then
            run_terminal(display)
            break
        elseif action == "Process" then
            run_process(display)
            break
        end

        ::continue::
    end
end

run()
os.exit(0)
