#!/usr/bin/lua

-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

local HOME = os.getenv("HOME")
local DIR = HOME .. "/.config/rofi/scripts/cliphist"
local TEXT_THEME = DIR .. "/cliphist.rasi"
local IMG_THEME = DIR .. "/cliphist-img.rasi"
local CACHE = (os.getenv("XDG_CACHE_HOME") or HOME .. "/.cache") .. "/cliphist-rofi"
local TMP_OPEN = "/tmp/cliphist-open"
local THUMB = 256
local PREVIEW_MAX = 120
local MODE_KEYS = "Tab"
local MODE_HINT = "tab: toggle mode ~ delete: remove entry"
local DELETE_KEYS = "Delete"
local DEBOUNCE_MS = 750
local DEBUG = os.getenv("CLIPHIST_DEBUG") == "1"
local LOG = (os.getenv("XDG_CACHE_HOME") or HOME .. "/.cache") .. "/cliphist-rofi/debug.log"

local args = { ... }
local image_mode = false
for _, a in ipairs(args) do
    if a == "--image" or a == "-i" then
        image_mode = true
    end
end

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function trim(s)
    local r = (s or ""):gsub("^%s*(.-)%s*$", "%1")
    return r
end

local function clean_text(s)
    s = s:gsub("\r", "")
    s = s:gsub("\0", "")
    s = s:gsub(string.char(0x1f), "")
    s = s:gsub("\n", " \u{21B5} ")
    s = s:gsub("%s+", " ")
    return s
end

local function now_ms()
    local h = io.popen("date +%s%3N")
    local t = h and h:read("*l") or "0"
    if h then h:close() end
    return tonumber(t) or 0
end

local function log_debug(msg)
    if not DEBUG then return end
    local h = io.open(LOG, "a")
    if h then
        h:write(os.date("%H:%M:%S") .. " " .. msg .. "\n")
        h:close()
    end
end

local function show_error(msg, theme)
    os.execute(string.format("rofi -e %s -theme %s",
        shell_quote(msg), shell_quote(theme)))
end

local function run_rofi(rows, theme, mesg)
    if #rows == 0 then return -1, -1 end
    local input = table.concat(rows, "\n") .. "\n"
    local in_tmp = os.tmpname()
    local out_tmp = os.tmpname()
    local f = assert(io.open(in_tmp, "wb"))
    f:write(input)
    f:close()
    local cmd = string.format(
        "rofi -dmenu -i -no-custom -format i -kb-custom-1 %s -kb-custom-2 %s -theme %s -mesg %s < %s > %s 2>/dev/null",
        shell_quote(MODE_KEYS), shell_quote(DELETE_KEYS), shell_quote(theme), shell_quote(mesg),
        shell_quote(in_tmp), shell_quote(out_tmp))
    local ok, _, code = os.execute(cmd)
    os.remove(in_tmp)
    local h = io.open(out_tmp, "rb")
    local out = h and h:read("*a") or ""
    if h then h:close() end
    os.remove(out_tmp)
    local ec = ok and 0 or (code or 0)
    local idx = tonumber(trim(out))
    if idx then return idx, ec end
    return -1, ec
end

local function list()
    local h = io.popen("cliphist list")
    if not h then return {}, {} end
    local text_entries, img_entries = {}, {}
    for line in h:lines() do
        local id, content = line:match("^(%d+)\t(.*)$")
        if id then
            if content:match("^%[%[ binary") then
                img_entries[#img_entries + 1] = id
            else
                text_entries[#text_entries + 1] = { id = id, content = content }
            end
        end
    end
    h:close()
    return text_entries, img_entries
end

local function build_text_rows(entries)
    local rows = {}
    for _, e in ipairs(entries) do
        local preview = clean_text(e.content)
        if preview == "" then preview = "(empty)" end
        if #preview > PREVIEW_MAX then
            preview = preview:sub(1, PREVIEW_MAX) .. "…"
        end
        rows[#rows + 1] = preview
    end
    return rows
end

local function missing_thumbs(ids)
    os.execute("mkdir -p " .. shell_quote(CACHE))
    local missing = {}
    for _, id in ipairs(ids) do
        local f = io.open(CACHE .. "/" .. id .. ".png", "rb")
        if f then
            f:close()
        else
            missing[#missing + 1] = id
        end
    end
    return missing
end

local function thumb_cmd(ids)
    if #ids == 0 then return nil end
    return string.format(
        "printf '%%s\\n' %s | xargs -P 8 -I{} sh -c " ..
        "'printf \"%%s\" \"{}\" | cliphist decode | magick - -thumbnail %dx%d " ..
        "-background none -gravity center -extent %dx%d \"%s/{}.png\" >/dev/null 2>&1'",
        table.concat(ids, " "), THUMB, THUMB, THUMB, THUMB, CACHE)
end

local function ensure_thumbs(ids)
    local cmd = thumb_cmd(missing_thumbs(ids))
    if cmd then os.execute(cmd) end
end

local function build_image_rows(ids)
    local rows = {}
    for _, id in ipairs(ids) do
        rows[#rows + 1] = "\0icon\x1f" .. CACHE .. "/" .. id .. ".png"
    end
    return rows
end

local function restore(id)
    local tmp = os.tmpname()
    os.execute(string.format("printf '%%s' %s | cliphist decode > %s",
        shell_quote(id), shell_quote(tmp)))
    local f = io.open(tmp, "rb")
    local ok = false
    if f then
        ok = f:seek("end") > 0
        f:close()
    end
    if ok then
        os.execute(string.format("wl-copy < %s", shell_quote(tmp)))
    else
        log_debug("decode failed or empty; skipped")
    end
    os.remove(tmp)
end

local function restore_image(id)
    log_debug("restore_image id=" .. tostring(id))
    os.execute("mkdir -p " .. shell_quote(TMP_OPEN))
    os.execute(string.format(
        "find %s -type f -name '*.png' -mmin +30 -delete 2>/dev/null",
        shell_quote(TMP_OPEN)))
    local path = TMP_OPEN .. "/" .. id .. ".png"
    os.execute(string.format("printf '%%s' %s | cliphist decode > %s",
        shell_quote(id), shell_quote(path)))
    local f = io.open(path, "rb")
    local ok = false
    if f then
        ok = f:seek("end") > 0
        f:close()
    end
    if ok then
        os.execute(string.format("wl-copy < %s", shell_quote(path)))
        os.execute(string.format("xdg-open %s >/dev/null 2>&1 &",
            shell_quote(path)))
    else
        log_debug("decode failed or empty; skipped")
    end
end

local CUSTOM_1 = 10
local CUSTOM_2 = 11
local last_toggle = 0
local last_delete = 0

if not image_mode then
    local _, img_ids = list()
    local cmd = thumb_cmd(missing_thumbs(img_ids))
    if cmd then
        os.execute("(" .. cmd .. ") >/dev/null 2>&1 &")
    end
end

while true do
    local text_entries, img_entries = list()

    if image_mode then
        if #img_entries == 0 and #text_entries > 0 then
            image_mode = false
        end
    else
        if #text_entries == 0 and #img_entries > 0 then
            image_mode = true
        end
    end

    local rows, theme

    if image_mode then
        ensure_thumbs(img_entries)
        if #img_entries == 0 then
            show_error("No clipboard entries", IMG_THEME)
            break
        end
        rows = build_image_rows(img_entries)
        theme = IMG_THEME
    else
        if #text_entries == 0 then
            show_error("No clipboard entries", TEXT_THEME)
            break
        end
        rows = build_text_rows(text_entries)
        theme = TEXT_THEME
    end

    local mesg = MODE_HINT

    local idx, ec = run_rofi(rows, theme, mesg)
    log_debug(string.format("mode=%s theme=%s ec=%d idx=%d",
        image_mode and "img" or "txt", theme, ec, idx))

    if ec == CUSTOM_1 then
        local now = now_ms()
        if now - last_toggle >= DEBOUNCE_MS then
            last_toggle = now
            image_mode = not image_mode
            log_debug("toggle -> " .. (image_mode and "img" or "txt"))
        else
            log_debug("toggle debounced")
        end
    elseif ec == CUSTOM_2 then
        local now = now_ms()
        if now - last_delete >= DEBOUNCE_MS and idx >= 0 then
            last_delete = now
            local id = image_mode and img_entries[idx + 1] or text_entries[idx + 1].id
            os.execute(string.format("printf '%%s' %s | cliphist delete",
                shell_quote(id)))
            os.remove(CACHE .. "/" .. id .. ".png")
            log_debug("deleted id=" .. tostring(id))
        else
            log_debug("delete debounced or no selection")
        end
    else
        if idx >= 0 then
            if image_mode then
                restore_image(img_entries[idx + 1])
            else
                restore(text_entries[idx + 1].id)
            end
        end
        break
    end
end
