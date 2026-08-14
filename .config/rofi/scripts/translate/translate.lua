#!/usr/bin/env lua

-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- Resolve our own directory so the tree can live anywhere.
local DIR = (arg[0] or debug.getinfo(1, "S").source:match("^@(.+)$") or ""):match("^(.*)/") or "."
if DIR == "." then DIR = os.getenv("PWD") or "."
elseif DIR:sub(1, 1) ~= "/" then DIR = (os.getenv("PWD") or ".") .. "/" .. DIR end

local HOME = os.getenv("HOME")
local CACHE = os.getenv("XDG_CACHE_HOME") or HOME .. "/.cache"
local USAGE_FILE = CACHE .. "/translate-usage"
local HISTORY_FILE = CACHE .. "/translate-history"
local HISTORY_MAX = 20

local ROFI_THEME_INPUT = DIR .. "/translate.rasi"
local ROFI_THEME_SELECT = DIR .. "/select.rasi"
local ROFI_THEME_RESULTS = DIR .. "/translate-output.rasi"
local MAX_LINE_LENGTH = 80
local MAX_LINES = 20
local MAX_SOURCE_LEN = 120
local TTS_MAX_CHARS = 180

-- Wikimedia-style UA; Google's endpoints are unauthenticated but a bare curl
-- UA is a common throttle trigger
local USER_AGENT = "rofi-translate/1.0 (https://github.com/kbuckleys/)"

local COLOR_HEAD = "#9bbfbf"
local COLOR_KEY = "#a2a8bc"
local COLOR_POS = "#6a707f"
local COLOR_EX = "#eebebe"
local COLOR_BODY = "#dfdfdd"
local COLOR_ERROR = "#e78284"
local ICON_TRANSLATE = "\u{f05ca}"
local ICON_STAR = "\u{f02da}"

-- JSON parsing
local json = require("cjson")

-- Target languages, native name + Google Translate code. Curated to the
-- languages Google actually voices well; source language is auto-detected.
local LANGS = {
    { "ar", "العربية" },
    { "bg", "Български" },
    { "bn", "বাংলা" },
    { "ca", "Català" },
    { "cs", "Čeština" },
    { "da", "Dansk" },
    { "de", "Deutsch" },
    { "el", "Ελληνικά" },
    { "en", "English" },
    { "es", "Español" },
    { "et", "Eesti" },
    { "fa", "فارسی" },
    { "fi", "Suomi" },
    { "fil", "Filipino" },
    { "fr", "Français" },
    { "gu", "ગુજરાતી" },
    { "he", "עברית" },
    { "hi", "हिन्दी" },
    { "hr", "Hrvatski" },
    { "hu", "Magyar" },
    { "id", "Indonesia" },
    { "it", "Italiano" },
    { "ja", "日本語" },
    { "kn", "ಕನ್ನಡ" },
    { "ko", "한국어" },
    { "lt", "Lietuvių" },
    { "lv", "Latviešu" },
    { "ml", "മലയാളം" },
    { "mr", "मराठी" },
    { "ms", "Bahasa Melayu" },
    { "nl", "Nederlands" },
    { "no", "Norsk" },
    { "pl", "Polski" },
    { "pt", "Português" },
    { "pt-BR", "Português (Brasil)" },
    { "ro", "Română" },
    { "ru", "Русский" },
    { "sk", "Slovenčina" },
    { "sl", "Slovenščina" },
    { "sr", "Српски" },
    { "sv", "Svenska" },
    { "sw", "Kiswahili" },
    { "ta", "தமிழ்" },
    { "te", "తెలుగు" },
    { "th", "ไทย" },
    { "tr", "Türkçe" },
    { "uk", "Українська" },
    { "ur", "اردو" },
    { "vi", "Tiếng Việt" },
    { "zh-CN", "简体中文" },
    { "zh-TW", "繁體中文" },
}

-- Reverse lookup for the source language Google reports back. A few codes
-- Google returns that don't appear verbatim in the list above.
local SOURCE_NAMES = {}
for _, l in ipairs(LANGS) do SOURCE_NAMES[l[1]] = l[2] end
SOURCE_NAMES["iw"] = SOURCE_NAMES["iw"] or "עברית"
SOURCE_NAMES["jw"] = SOURCE_NAMES["jw"] or "Jawa"

local function source_name(code)
    return SOURCE_NAMES[code] or (code and code:upper() or "")
end

-- Percent-encode for use in a URL query value
local function urlencode(str)
    return (str:gsub("[^%w%-%_%.%~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- Shell command with output
local function shell(cmd)
    local handle = io.popen(cmd, "r")
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    return result
end

-- Read file contents
local function read_file(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local content = f:read("*a")
    f:close()
    return content
end

-- Write string to file
local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

-- Safely remove a file
local function remove_file(path)
    os.remove(path)
end

-- Shell-escape a string (single-quote it)
local function shell_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Escape for rofi markup
local function escape_markup(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    return s
end

-- Check if string has any non-whitespace content. %S matches any UTF-8 byte,
-- so text in any script (CJK, Arabic, Cyrillic, ...) counts, unlike [%w] which
-- is ASCII-only and made non-English input look empty.
local function has_content(s)
    return s:match("%S") ~= nil
end

-- Simple word wrap
local function wrap(text, width)
    local lines = {}
    for raw_line in text:gmatch("[^\n]+") do
        local line = raw_line
        while #line > width do
            local break_at = width
            local space = line:sub(1, width):match(".*()%s")
            if space and space > 1 then
                break_at = space
            end
            lines[#lines + 1] = line:sub(1, break_at - 1)
            line = line:sub(break_at + 1)
        end
        lines[#lines + 1] = line
    end
    return lines
end

local function truncate(text, max)
    if #text <= max then return text end
    return text:sub(1, max) .. "…"
end

--------------------------------------------------------------------------------
-- System tools
--------------------------------------------------------------------------------

local PLAYER = (function()
    local candidates = {
        { "mpv", "mpv --no-video --really-quiet" },
        { "mpg123", "mpg123 -q" },
        { "ffplay", "ffplay -nodisp -autoexit -loglevel quiet" },
        { "paplay", "paplay" },
    }
    for _, c in ipairs(candidates) do
        local found = shell("command -v " .. c[1] .. " 2>/dev/null")
        if found and found:match("%S") then return c[2] end
    end
    return nil
end)()

local CLIP = (function()
    local candidates = {
        { "wl-copy", "wl-copy" },
        { "xclip", "xclip -selection clipboard" },
        { "xsel", "xsel --clipboard --input" },
        { "pbcopy", "pbcopy" },
    }
    for _, c in ipairs(candidates) do
        local found = shell("command -v " .. c[1] .. " 2>/dev/null")
        if found and found:match("%S") then return c[2] end
    end
    return nil
end)()

local function file_size(path)
    local f = io.open(path, "r")
    if not f then return 0 end
    local size = f:seek("end")
    f:close()
    return size
end

-- Start the download while the user is still reading the translation, so
-- Return doesn't stall on the network. Downloads to a .part file and renames,
-- so a half-written file is never played. Returns the temp path.
local function prefetch_audio(text, code)
    if not PLAYER or not text or text == "" then return nil end

    local audio = text:sub(1, TTS_MAX_CHARS)
    local path = os.tmpname()
    local part = path .. ".part"
    local url = "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl="
        .. urlencode(code) .. "&total=1&idx=0&textlen=" .. #audio
        .. "&q=" .. urlencode(audio)
    os.execute(string.format(
        "( curl -sL --max-time 12 -A %s %s -o %s && mv -f %s %s ) >/dev/null 2>&1 &",
        shell_quote(USER_AGENT), shell_quote(url),
        shell_quote(part), shell_quote(part), shell_quote(path)))
    return path
end

-- Fire and forget. The player is detached so rofi can be back on screen
-- immediately rather than waiting out the clip.
local function play_audio(path)
    if not PLAYER or not path then return false end

    -- Normally already done; only waits if Return came fast
    for _ = 1, 20 do
        if file_size(path) > 0 then break end
        os.execute("sleep 0.1")
    end
    if file_size(path) == 0 then return false end

    os.execute("setsid " .. PLAYER .. " " .. shell_quote(path) .. " >/dev/null 2>&1 &")
    return true
end

local function copy_clip(text)
    if not CLIP or not text or text == "" then return false end
    os.execute(string.format("printf '%%s' %s | %s >/dev/null 2>&1",
        shell_quote(text), CLIP))
    return true
end

--------------------------------------------------------------------------------
-- Language usage ranking
--------------------------------------------------------------------------------

-- Read the per-language usage counts, code -> count
local function load_usage()
    local usage = {}
    for line in read_file(USAGE_FILE):gmatch("[^\n]+") do
        local code, n = line:match("^(%S+)%s+(%d+)$")
        if code then usage[code] = tonumber(n) or 0 end
    end
    return usage
end

-- Increment the count for a used language so it floats to the top of the picker
local function bump_usage(code)
    local usage = load_usage()
    usage[code] = (usage[code] or 0) + 1
    local lines = {}
    for c, n in pairs(usage) do
        if n > 0 then lines[#lines + 1] = c .. " " .. n end
    end
    shell("mkdir -p " .. shell_quote(CACHE))
    if #lines > 0 then
        write_file(USAGE_FILE, table.concat(lines, "\n") .. "\n")
    end
end

--------------------------------------------------------------------------------
-- Google Translate
--------------------------------------------------------------------------------

-- Recognised Google source codes. Used to validate an optional "<code>: "
-- prefix so "no: way" isn't read as source code "no" (Norwegian).
local KNOWN_CODES = {}
for _, c in ipairs({
    "af","sq","am","ar","hy","az","eu","be","bn","bs","bg","ca","ceb","zh-CN",
    "zh-TW","co","hr","cs","da","nl","en","eo","et","fi","fr","fy","gl","ka","de",
    "el","gu","ht","ha","haw","he","hi","hmn","hu","is","ig","id","ga","it","ja",
    "jv","kn","kk","km","ko","ku","ky","lo","la","lv","lt","lb","mk","mg","ms",
    "ml","mt","mi","mr","mn","my","ne","no","ny","or","ps","fa","pl","pt","pa",
    "ro","ru","sm","gd","sr","st","sn","sd","si","sk","sl","so","es","su","sw",
    "sv","tg","ta","te","th","tr","tk","uk","ur","ug","uz","vi","cy","xh","yi",
    "yo","zu","iw","jw",
}) do KNOWN_CODES[c] = true end

local function translate_url(text, code, source)
    local sl = source and KNOWN_CODES[source] and source or "auto"
    return "https://translate.googleapis.com/translate_a/single?client=gtx&sl="
        .. sl .. "&tl=" .. urlencode(code) .. "&dt=t&dt=rm&q=" .. urlencode(text)
end

-- Fetch and parse a translation. Returns { translation, roman, source }, or
-- nil + an error kind ("network" / "empty").
local function do_translate(text, code, source)
    local url = translate_url(text, code, source)
    local body = shell(string.format("curl -s --max-time 12 -A %s %s",
        shell_quote(USER_AGENT), shell_quote(url)))
    if not body or body == "" then return nil, "network" end

    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= "table" or type(data[1]) ~= "table" then
        return nil, "network"
    end

    local parts, roman = {}, nil
    for _, seg in ipairs(data[1]) do
        if type(seg) == "table" then
            -- seg[1] translation, seg[2] source echo, seg[3] transliteration
            if type(seg[1]) == "string" and seg[1] ~= "" then
                parts[#parts + 1] = seg[1]
            end
            if not roman and type(seg[3]) == "string" and seg[3] ~= "" then
                roman = seg[3]
            end
        end
    end

    if #parts == 0 then return nil, "empty" end

    local source = type(data[3]) == "string" and data[3] or nil
    return { translation = table.concat(parts), roman = roman, source = source }
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

-- A small "key action <sep> key action" row for the bottom of the message bar.
-- Keys are bold COLOR_KEY; descriptions are the dim COLOR_POS.
local function hint_row(bindings)
    local parts = {}
    for _, b in ipairs(bindings) do
        parts[#parts + 1] = "<b><span foreground=\"" .. COLOR_KEY .. "\">" ..
            escape_markup(b[1]) .. "</span></b> <span foreground=\"" .. COLOR_POS .. "\">" ..
            escape_markup(b[2]) .. "</span>"
    end
    return "<span size=\"small\">" ..
        table.concat(parts, "    ") .. "</span>"
end

local function build_message(text, lang, t, audio_enabled, swapped)
    local head = swapped and truncate(t.translation, MAX_SOURCE_LEN) or truncate(text, MAX_SOURCE_LEN)
    local msg = "<span foreground=\"" .. COLOR_HEAD .. "\">" .. ICON_TRANSLATE .. "</span>  " ..
        "<b><span foreground=\"" .. COLOR_HEAD .. "\">" ..
        escape_markup(head) .. "</span></b>"
    msg = msg .. "\n<span foreground=\"" .. COLOR_POS .. "\">" .. escape_markup(lang.name) .. "</span>"
    if t.source then
        msg = msg .. " <span foreground=\"" .. COLOR_POS .. "\">→ from " ..
            escape_markup(source_name(t.source)) .. "</span>"
    end

    local keys = {}
    keys[#keys + 1] = { "c", "copy" }
    keys[#keys + 1] = { "s", "swap" }
    if audio_enabled then keys[#keys + 1] = { "return", "speak" } end
    keys[#keys + 1] = { "tab", "other language" }
    keys[#keys + 1] = { "backspace", "back" }
    keys[#keys + 1] = { "esc", "close" }

    return msg .. "\n" .. hint_row(keys)
end

local function build_lines(text, roman)
    local lines = {}

    for _, wline in ipairs(wrap(text, MAX_LINE_LENGTH)) do
        lines[#lines + 1] = "<b><span foreground=\"" .. COLOR_BODY .. "\">" ..
            escape_markup(wline) .. "</span></b>"
    end

    if roman and roman ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "<span foreground=\"" .. COLOR_POS .. "\"><i>Pronunciation</i></span>"
        for _, wline in ipairs(wrap(roman, MAX_LINE_LENGTH)) do
            lines[#lines + 1] = "<span foreground=\"" .. COLOR_EX .. "\"><i>" ..
                escape_markup(wline) .. "</i></span>"
        end
    end

    while #lines > 0 and lines[#lines] == "" do
        lines[#lines] = nil
    end

    return lines
end

-- Run rofi over `input_file`, returning its exit code and the selected line
local function run_rofi(args, input_file)
    local outfile = os.tmpname()
    local cmd = string.format("rofi %s < %s > %s 2>/dev/null",
        args, shell_quote(input_file), shell_quote(outfile))

    local ok, _, code = os.execute(cmd)
    local out = read_file(outfile)
    remove_file(outfile)

    if type(ok) == "number" then code = ok end
    return code or 0, trim(out)
end

-- Show a results screen. Returns rofi's exit code:
--   0  Return      play the audio again
--   13 c           copy the shown text to the clipboard
--   10 Tab         pick another target language for the same text
--   11 BackSpace   back to the text prompt
--   12 s          swap output between target and source text
--   1  Escape      close
local function show_results(lines, message)
    local tmpfile = os.tmpname()
    write_file(tmpfile, #lines > 0 and (table.concat(lines, "\n") .. "\n") or "\n")

    -- BackSpace ships bound to kb-remove-char-back and Tab to kb-element-next;
    -- leaving either in place makes a double binding and rofi rejects it.
    -- Nothing is typed on this screen, so dropping the editing/navigation keys
    -- costs nothing. A bare "s" is unbound by default and used to swap views.
    local binds = ' -kb-remove-char-back "" -kb-element-next ""' ..
        ' -kb-custom-1 "Tab" -kb-custom-2 "BackSpace" -kb-custom-3 "s" -kb-custom-4 "c"'

    local n_lines = math.max(1, math.min(#lines, MAX_LINES))
    local args = string.format(
        '-dmenu -wayland-layer top -theme %s -no-sort -lines %d -p "Translation" -markup-rows%s%s',
        shell_quote(ROFI_THEME_RESULTS),
        n_lines,
        message ~= "" and (" -mesg " .. shell_quote(message)) or "",
        binds
    )

    local code = run_rofi(args, tmpfile)
    remove_file(tmpfile)
    return code
end

local function error_text(err)
    if err == "network" then
        return "Network error — couldn't reach Google Translate"
    end
    return "No translation returned for that text"
end

local function show_error(text)
    local msg = "<span foreground=\"" .. COLOR_ERROR .. "\">" .. escape_markup(text) .. "</span>"
    return show_results({ msg }, "")
end

--------------------------------------------------------------------------------
-- Prompts
--------------------------------------------------------------------------------

-- Second screen: pick a target language. Most-used languages float to the top,
-- each marked with a star; the rest keep their curated order. Returns
-- { code, name } or nil to go back.
local function pick_language()
    local usage = load_usage()
    local order = {}
    for i = 1, #LANGS do order[i] = i end
    table.sort(order, function(a, b)
        local ua, ub = usage[LANGS[a][1]] or 0, usage[LANGS[b][1]] or 0
        if ua ~= ub then return ua > ub end
        return a < b
    end)

    local rows = {}
    for _, i in ipairs(order) do
        local l = LANGS[i]
        local used = (usage[l[1]] or 0) > 0
        rows[#rows + 1] = (used and (ICON_STAR .. " ") or "") .. l[2] .. " (" .. l[1] .. ")"
    end
    local hist_file = os.tmpname()
    write_file(hist_file, table.concat(rows, "\n") .. "\n")

    local mesg = hint_row({ { "return", "pick" }, { "esc", "back" } })
    local args = string.format(
        '-dmenu -i -no-custom -wayland-layer top -theme %s -no-sort -p "Translate to" -mesg %s',
        shell_quote(ROFI_THEME_SELECT), shell_quote(mesg))

    local code, out = run_rofi(args, hist_file)
    remove_file(hist_file)

    if code ~= 0 then return nil end
    local lcode = out:match("%(([%w%-]+)%)%s*$")
    if not lcode then return nil end
    for _, l in ipairs(LANGS) do
        if l[1] == lcode then return { code = lcode, name = l[2] } end
    end
    return { code = lcode, name = lcode }
end

-- Marker returned by prompt_for_text() when the user confirms an empty box,
-- meaning "show the translation history" instead of quitting.
local HISTORY_MARKER = { history = true }

-- First screen: the text to translate. An optional leading "<code>: " prefix
-- (e.g. "ja: こんにちは") forces the source language; otherwise it's
-- auto-detected. Returns a payload table, the history marker, or nil to quit.
local function prompt_for_text()
    local empty = os.tmpname()
    write_file(empty, "")

    local mesg = "<span foreground=\"" .. COLOR_HEAD .. "\">" .. ICON_TRANSLATE .. "</span>" ..
        "\n" .. hint_row({ { "return", "pick language / history" }, { "esc", "quit" } })
    local args = string.format(
        '-dmenu -wayland-layer top -theme %s -no-sort -p "Text" -mesg %s',
        shell_quote(ROFI_THEME_INPUT), shell_quote(mesg))

    local code, raw = run_rofi(args, empty)
    remove_file(empty)

    if code ~= 0 then return nil end
    if not has_content(raw) then return HISTORY_MARKER end

    local out = trim(raw)
    local scode, rest = out:match("^(%S+)%s*:%s*(%S.*)$")
    if scode and KNOWN_CODES[scode] and has_content(rest) then
        return { text = rest, source = scode }
    end
    return { text = out }
end

--------------------------------------------------------------------------------
-- Translation history
--------------------------------------------------------------------------------

-- Most-recent-first list of saved translations: { code, source?, text, translation }
local function load_history()
    local entries = {}
    for line in read_file(HISTORY_FILE):gmatch("[^\n]+") do
        local ok, e = pcall(json.decode, line)
        if ok and type(e) == "table" and type(e.code) == "string" and type(e.text) == "string" then
            entries[#entries + 1] = {
                code = e.code, source = e.source, text = e.text, translation = e.translation
            }
        end
    end
    return entries
end

local function save_history(entries)
    local lines = {}
    for _, e in ipairs(entries) do
        lines[#lines + 1] = json.encode(e)
    end
    shell("mkdir -p " .. shell_quote(CACHE))
    if #lines > 0 then
        write_file(HISTORY_FILE, table.concat(lines, "\n") .. "\n")
    else
        os.remove(HISTORY_FILE)
    end
end

-- Record a used pair, most recent first, deduped by code+text, capped.
local function add_history(code, source, text, translation)
    if not text or text == "" then return end
    local out = { { code = code, source = source, text = text, translation = translation } }
    local n = 1
    for _, e in ipairs(load_history()) do
        if e.code == code and e.text == text then
            -- replace the older duplicate
        elseif n < HISTORY_MAX then
            out[#out + 1] = e
            n = n + 1
        end
    end
    save_history(out)
end

-- Remove one pair from history.
local function delete_history(code, text)
    local out = {}
    for _, e in ipairs(load_history()) do
        if not (e.code == code and e.text == text) then
            out[#out + 1] = e
        end
    end
    save_history(out)
end

-- One-line row for a history entry: "text → translation (lang)"
local function history_row(e)
    local lang = source_name(e.code)
    local t = escape_markup(truncate((e.text or ""):gsub("\n", " "), 45))
    local trans = escape_markup(truncate((e.translation or ""):gsub("\n", " "), 45))
    return t .. "  →  " .. trans .. "  (" .. escape_markup(lang) .. ")"
end

-- Pick a saved translation. Delete removes the highlighted entry and refreshes.
-- Returns the entry to re-translate, or nil to go back.
local function show_history()
    while true do
        local entries = load_history()
        if #entries == 0 then return nil end

        local rows = {}
        for _, e in ipairs(entries) do rows[#rows + 1] = history_row(e) end
        local hist_file = os.tmpname()
        write_file(hist_file, table.concat(rows, "\n") .. "\n")

        -- Delete is bound by default to both kb-delete-entry and
        -- kb-remove-char-forward; leaving either in place makes a double binding
        -- and rofi rejects it. Rebind to a custom key so we can persist.
        local binds = ' -kb-delete-entry "" -kb-remove-char-forward "" -kb-custom-1 "Delete"'
        local mesg = hint_row({
            { "return", "re-translate" }, { "delete", "remove" }, { "esc", "back" }
        })
        local args = string.format(
            '-dmenu -i -no-custom -wayland-layer top -theme %s -no-sort -p "History" -mesg %s%s',
            shell_quote(ROFI_THEME_SELECT), shell_quote(mesg), binds)

        local code, out = run_rofi(args, hist_file)
        remove_file(hist_file)

        if code == 0 then
            for i, e in ipairs(entries) do
                if out == rows[i] then return e end
            end
            return nil
        elseif code == 10 then
            for i, e in ipairs(entries) do
                if out == rows[i] then
                    delete_history(e.code, e.text)
                    break
                end
            end
        else
            return nil
        end
    end
end

--------------------------------------------------------------------------------
-- Debug mode
--------------------------------------------------------------------------------

if arg[1] == "--debug" then
    local code = "es"
    local source = nil
    local text = arg[2]
    if arg[3] then
        code = arg[2]
        text = arg[3]
    end
    if arg[4] then
        code = arg[2]
        source = arg[3]
        text = arg[4]
    end
    if not text then
        io.stderr:write("usage: translate.lua --debug [<code>] [<source>] <text>\n")
        os.exit(1)
    end

    print("### target: " .. code .. " (" .. source_name(code) .. ") ###")
    if source then print("### source override: " .. source .. " ###") else print("### source: auto ###") end
    print("### language list: " .. #LANGS .. " entries ###")
    local usage = load_usage()
    local used = 0
    for _ in pairs(usage) do used = used + 1 end
    print("### usage: " .. used .. " languages ranked ###")
    print("### player: " .. tostring(PLAYER) .. " ###")
    print("### clip: " .. tostring(CLIP) .. " ###")

    local url = translate_url(text, code, source)
    print("### url: " .. url .. " ###")
    local body = shell(string.format("curl -s --max-time 12 -A %s %s",
        shell_quote(USER_AGENT), shell_quote(url)))
    print("### body: " .. tostring(body) .. " ###")

    local t, err = do_translate(text, code, source)
    if not t then
        print("### translate failed: " .. tostring(err) .. " ###")
        os.exit(1)
    end

    print("### source: " .. tostring(t.source) .. " (" .. source_name(t.source) .. ") ###")
    print("### translation: " .. t.translation .. " ###")
    print("### roman: " .. tostring(t.roman) .. " ###")

    print("### rendered ###")
    print(build_message(text, { code = code, name = source_name(code) }, t, PLAYER ~= nil))
    for _, l in ipairs(build_lines(t.translation, t.roman)) do print(l) end

    os.exit(0)
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

-- Player process for the most recent audio clip, so it can be stopped on exit.
local LAST_AUDIO = nil
local function cleanup_audio()
    if PLAYER and LAST_AUDIO then
        os.execute("pkill -f " .. shell_quote(LAST_AUDIO) .. " >/dev/null 2>&1")
    end
end

-- Translate `text` to `lang`, then run the results phase. Records a history
-- entry for every successful translation. Returns true if the user chose to quit.
local function translate_and_show(text, lang, source)
    local t, err = do_translate(text, lang.code, source)
    if not t then
        -- Esc on the error returns to whoever called us.
        show_error(error_text(err))
        return false
    end
    add_history(lang.code, source, text, t.translation)
    bump_usage(lang.code)
    local audio_enabled = PLAYER ~= nil

    -- Results phase for this text. c copies and reopens so it can be done
    -- again; Return replays the audio; Tab re-picks the target language
    -- for the same text; Alt+Tab swaps between the translation and the source
    -- text; Backspace returns to the text prompt; Escape closes.
    local quit, keep = false, true
    local swapped = false
    local audio_paths = {}
    while keep and not quit do
        local again, code
        repeat
            local shown_text = swapped and text or t.translation
            local shown_code = swapped and t.source or lang.code
            local audio_path
            if audio_enabled and shown_code then
                audio_path = prefetch_audio(shown_text, shown_code)
                if audio_path then
                    audio_paths[#audio_paths + 1] = audio_path
                    LAST_AUDIO = audio_path
                end
            end
            local message = build_message(text, lang, t, audio_enabled, swapped)
            local lines = swapped and build_lines(text) or build_lines(t.translation, t.roman)

            code = show_results(lines, message)
            if code == 0 then
                again = audio_path ~= nil and play_audio(audio_path)
            elseif code == 13 then
                copy_clip(shown_text)
                again = true
            elseif code == 10 then
                again = false
            elseif code == 12 then
                swapped = not swapped
                again = true
            else
                again = false
                if code == 1 then quit = true end
            end
        until not again

        if code == 10 and not quit then
            local new_lang = pick_language()
            if not new_lang then
                -- Esc on the re-pick selector: back to the results we were on
                keep = true
            else
                local t2, err2 = do_translate(text, new_lang.code, source)
                if not t2 then
                    show_error(error_text(err2))
                    -- Esc on the error: back to the results we were on
                    keep = true
                else
                    lang, t = new_lang, t2
                    swapped = false
                    add_history(lang.code, source, text, t.translation)
                    bump_usage(lang.code)
                end
            end
        else
            keep = false
        end
    end

    for _, p in ipairs(audio_paths) do
        remove_file(p)
        remove_file(p .. ".part")
    end

    return quit
end

while true do
    local p = prompt_for_text()
    if not p then break end

    if p.history then
        -- Empty text: offer saved translations instead of quitting.
        local entry = show_history()
        if entry then
            local lang = { code = entry.code, name = source_name(entry.code) }
            if translate_and_show(entry.text, lang, entry.source) then break end
        end
    else
        local lang = pick_language()
        if lang then
            if translate_and_show(p.text, lang, p.source) then break end
        end
    end
end

cleanup_audio()
