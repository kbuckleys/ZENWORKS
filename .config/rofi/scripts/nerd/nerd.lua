#!/usr/bin/env lua

-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- Resolve our own directory so the tree can live anywhere.
local DIR = (arg[0] or debug.getinfo(1, "S").source:match("^@(.+)$") or ""):match("^(.*)/") or "."
if DIR == "." then DIR = os.getenv("PWD") or "."
elseif DIR:sub(1, 1) ~= "/" then DIR = (os.getenv("PWD") or ".") .. "/" .. DIR end
local THEME = DIR .. "/nerd.rasi"
local OK_THEME = DIR .. "/nerdok.rasi"

local CSS_URL = "https://www.nerdfonts.com/assets/css/webfont.css"
local FONT = "Symbols Nerd Font"
local GLYPH_COLOR = "#DFDFDD"
local GLYPH_SIZE = 200
local FORMATS = { "Icon", "Class", "UTF" }
local UTF_FORMAT = "U+%s"

local SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" ' ..
    'viewBox="0 0 %d %d"><text x="%d" y="%d" font-family="%s" font-size="%d" ' ..
    'fill="%s" text-anchor="middle">&#x%s;</text></svg>'

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function show_error(msg)
    os.execute(string.format("rofi -e %s -theme %s",
        shell_quote(msg), shell_quote(THEME)))
end

local function capture(cmd)
    local h = io.popen(cmd)
    if not h then return nil end
    local out = h:read("*a")
    h:close()
    return out
end

local function tmpdir()
    local tmp = os.getenv("TMPDIR") or "/tmp"
    -- sweep dirs left behind when a previous run was killed mid-pick
    os.execute("find '" .. tmp .. "' -maxdepth 1 -type d -name 'rofi-nerd.*' -mmin +10 " ..
        "-exec rm -rf {} + 2>/dev/null")
    local out = capture("mktemp -d '" .. tmp .. "/rofi-nerd.XXXXXXXX'")
    return out and out:gsub("\n$", "") or nil
end

local function run_rofi(rows, theme, mesg, selected)
    local in_tmp = os.tmpname()
    local out_tmp = os.tmpname()
    local f = assert(io.open(in_tmp, "wb"))
    f:write(table.concat(rows, "\n") .. "\n")
    f:close()
    os.execute(string.format(
        "rofi -dmenu -i -no-custom -format i -selected-row %d -theme %s -mesg %s < %s > %s 2>/dev/null",
        selected or 0, shell_quote(theme), shell_quote(mesg),
        shell_quote(in_tmp), shell_quote(out_tmp)))
    os.remove(in_tmp)
    local h = io.open(out_tmp, "rb")
    local out = h and h:read("*a") or ""
    if h then h:close() end
    os.remove(out_tmp)
    return tonumber((out:gsub("%s", "")))
end

-- always pulled fresh from nerdfonts.com, never written to a cache
local function fetch_icons()
    local css = capture(string.format(
        "curl -fsSL --compressed --max-time 20 " ..
        "-H 'Cache-Control: no-cache' -H 'Pragma: no-cache' %s 2>/dev/null",
        shell_quote(CSS_URL)))
    if not css or css == "" then return nil end

    local icons = {}
    for class, code in css:gmatch('%.(nf%-[%w_%-]+):before%s*{%s*content:%s*"\\(%x+)"') do
        icons[#icons + 1] = {
            class = class,
            code = code,
            char = utf8.char(tonumber(code, 16)),
        }
    end
    if #icons == 0 then return nil end
    return icons
end

local function render_glyphs(icons, dir)
    local half = GLYPH_SIZE // 2
    local baseline = math.floor(GLYPH_SIZE * 0.76)
    local size = math.floor(GLYPH_SIZE * 0.7)
    for i, icon in ipairs(icons) do
        icon.svg = string.format("%s/%s.svg", dir, icon.code)
        local f = io.open(icon.svg, "w")
        if f then
            f:write(string.format(SVG, GLYPH_SIZE, GLYPH_SIZE, GLYPH_SIZE, GLYPH_SIZE,
                half, baseline, FONT, size, GLYPH_COLOR, icon.code))
            f:close()
        end
    end
end

-- nerdok.rasi carries a "%s" placeholder for the preview of the picked glyph
local function build_ok_theme(icon, dir)
    local src = assert(io.open(OK_THEME, "rb"))
    local body = src:read("*a")
    src:close()
    body = body:gsub("%%s", function() return icon.svg end)

    local path = string.format("%s/nerdok-%s.rasi", dir, icon.code)
    local out = assert(io.open(path, "wb"))
    out:write(body)
    out:close()
    return path
end

local function value_for(icon, format)
    format = format:lower()
    if format == "icon" then
        return icon.char
    elseif format == "class" then
        return icon.class
    end
    return string.format(UTF_FORMAT, icon.code:upper())
end

local function main()
    local icons = fetch_icons()
    if not icons then
        show_error("Failed to fetch icons from nerdfonts.com")
        os.exit(1)
    end

    local dir = tmpdir()
    if not dir then
        show_error("Failed to create temporary directory")
        os.exit(1)
    end
    render_glyphs(icons, dir)

    local rows = {}
    for i, icon in ipairs(icons) do
        rows[i] = icon.class .. "\0icon\x1f" .. icon.svg
    end
    local mesg = string.format(
        "%d Icons  \u{F01D9}  return: pick format  \u{F01D9}  esc: quit", #icons)

    local selected = 0
    while true do
        local pick = run_rofi(rows, THEME, mesg, selected)
        if not pick then break end

        local icon = icons[pick + 1]
        if not icon then break end

        selected = pick
        local theme = build_ok_theme(icon, dir)
        local format = run_rofi(FORMATS, theme, icon.class, 0)
        os.remove(theme)

        if format then
            local value = value_for(icon, FORMATS[format + 1])
            os.execute(string.format("printf '%%s' %s | wl-copy", shell_quote(value)))
            break
        end
    end

    os.execute("rm -rf " .. shell_quote(dir))
end

main()
