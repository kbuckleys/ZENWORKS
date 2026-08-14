#!/usr/bin/env lua

-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- Resolve our own directory so the tree can live anywhere.
local DIR = (arg[0] or debug.getinfo(1, "S").source:match("^@(.+)$") or ""):match("^(.*)/") or "."
if DIR == "." then DIR = os.getenv("PWD") or "."
elseif DIR:sub(1, 1) ~= "/" then DIR = (os.getenv("PWD") or ".") .. "/" .. DIR end

local THEME = DIR .. "/rbw.rasi"

local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- rofi-rbw styles its own hint row internally; we disable it (--no-help) and
-- render an equivalent one here so the colors/dividers match the other launchers.
local KEY_FG = "#a2a8bc"
local DESC_FG = "#6a707f"
local function hint_pair(key, desc)
    return "<b><span foreground=\"" .. KEY_FG .. "\">" .. key .. "</span></b><span foreground=\"" ..
        DESC_FG .. "\">" .. desc .. "</span>"
end

-- The mesg spells out what each key does; rofi-rbw's real bindings are the
-- same keys, shown here in the lowercase hint style used across the launchers.
local bindings = {
    { "alt 1", "Type Username, Tab, Password" },
    { "alt 2", "Type Username" },
    { "alt 3", "Type Password" },
    { "alt 4", "Type Totp" },
    { "alt c", "Copy Password" },
    { "alt u", "Copy Username" },
    { "alt t", "Copy Totp" },
    { "alt m", "Menu" },
    { "alt s", "Sync logins" },
}
local parts = {}
for _, b in ipairs(bindings) do
    parts[#parts + 1] = hint_pair(b[1], b[2])
end
local mesg = table.concat(parts, "    ")

os.execute("rofi-rbw --no-help --selector-args=" ..
    shq("-theme " .. shq(THEME) .. " -mesg " .. shq(mesg)))
