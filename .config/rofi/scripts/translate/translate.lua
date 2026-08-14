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
local MAX_LINE_LENGTH = 96
local MAX_LINES = 20
local MAX_SOURCE_LEN = 120
local TTS_CHUNK_MAX = 190
local TTS_REQUEST_GAP = 0.25

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
SOURCE_NAMES["iw"] = "עברית"
SOURCE_NAMES["jw"] = "Jawa"

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

-- Length/substring that count UTF-8 characters and degrade to bytes on any
-- invalid input, so a mid-sequence cut can never crash the script. Lua 5.5's
-- utf8 library has no sub, so one is built from utf8.offset.
local function ulen(s)
    local ok, n = pcall(utf8.len, s)
    return (ok and n) or #s
end

local function usub(s, i, j)
    local ok, n = pcall(utf8.len, s)
    if not ok or not n then return s:sub(i, j) end
    if i < 0 then i = n + i + 1 end
    if j == nil then j = n elseif j < 0 then j = n + j + 1 end
    if i < 1 then i = 1 end
    if j > n then j = n end
    if i > j then return "" end
    local start = utf8.offset(s, i)
    if not start then return "" end
    local stop = utf8.offset(s, j + 1)
    if not stop then return s:sub(start) end
    return s:sub(start, stop - 1)
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

-- Simple word wrap. Operates on UTF-8 characters, not bytes, so a multi-byte
-- char is never split across lines.
local function wrap(text, width)
    local lines = {}
    for raw_line in text:gmatch("[^\n]+") do
        local line = raw_line
        local ok, len = pcall(utf8.len, line)
        if not ok or not len then len = #line end
        while len > width do
            local break_at, found = width, false
            for i = width, 2, -1 do
                if usub(line, i, i):match("%s") then
                    break_at, found = i, true
                    break
                end
            end
            if found then
                -- Cut after the last space in the window, dropping that space.
                lines[#lines + 1] = usub(line, 1, break_at - 1)
                line = usub(line, break_at + 1)
            else
                -- Unbroken run (URL, long word): cut exactly at the limit so
                -- no character is dropped.
                lines[#lines + 1] = usub(line, 1, width)
                line = usub(line, width + 1)
            end
            local ok2, l2 = pcall(utf8.len, line)
            len = (ok2 and l2) or #line
        end
        lines[#lines + 1] = line
    end
    return lines
end

-- Truncate by UTF-8 characters (not bytes) so a multi-byte char is never cut
-- mid-sequence, which would leave invalid UTF-8 that rofi mangles.
local function truncate(text, max)
    local ok, n = pcall(utf8.len, text)
    if not ok or not n then
        if #text <= max then return text end
        return text:sub(1, max) .. "…"
    end
    if n <= max then return text end
    return usub(text, 1, max) .. "…"
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

-- Split text into chunks Google's TTS will accept (a single request rejects
-- text over ~200 chars). Breaks at sentence boundaries where possible so the
-- speech stays natural, then packs sentences into chunks of at most
-- TTS_CHUNK_MAX chars, hard-splitting any sentence that alone exceeds it.
local function split_tts(text)
    local chunks, sentences = {}, {}
    for seg in text:gmatch("[^%.\n?。．！？]*[%.\n?。．！？]?") do
        local piece = seg:gsub("^%s+", "")
        if piece:match("%S") then sentences[#sentences + 1] = piece end
    end

    local cur = ""
    local function flush()
        if cur:match("%S") then chunks[#chunks + 1] = cur end
        cur = ""
    end

    for _, s in ipairs(sentences) do
        local slen = ulen(s)
        local clen = ulen(cur)
        if clen > 0 and clen + slen > TTS_CHUNK_MAX then
            flush()
        end
        if slen <= TTS_CHUNK_MAX then
            cur = cur .. s
        else
            local rest = s
            while ulen(rest) > TTS_CHUNK_MAX do
                chunks[#chunks + 1] = usub(rest, 1, TTS_CHUNK_MAX)
                rest = usub(rest, TTS_CHUNK_MAX + 1)
            end
            cur = rest
        end
    end
    flush()
    return chunks
end

-- Start the downloads while the user is still reading the translation, so
-- Return doesn't stall on the network. The whole paragraph is split into
-- sentence-aligned chunks; each is fetched with its own total/idx, then the
-- pieces are concatenated into a single file (all pieces share the encoder's
-- bitrate, so a plain cat is a valid MP3 stream). Returns the final path.
local function prefetch_audio(text, code)
    if not PLAYER or not text or text == "" then return nil end

    local chunks = split_tts(text)
    if #chunks == 0 then return nil end

    local path = os.tmpname()
    local part = path .. ".part"
    local n = #chunks

    local cmds, pieces = {}, {}
    for i, chunk in ipairs(chunks) do
        local url = "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl="
            .. urlencode(code) .. "&total=" .. n .. "&idx=" .. (i - 1)
            .. "&textlen=" .. #chunk .. "&q=" .. urlencode(chunk)
        local piece = path .. "." .. (i - 1)
        cmds[#cmds + 1] = string.format("curl -sL --max-time 12 -A %s %s -o %s",
            shell_quote(USER_AGENT), shell_quote(url), shell_quote(piece))
        pieces[#pieces + 1] = shell_quote(piece)
    end

    -- Fetch every chunk, then assemble; pieces are cleaned up either way.
    local sep = " && sleep " .. TTS_REQUEST_GAP .. " && "
    os.execute(string.format(
        "( %s; if [ $? -eq 0 ]; then cat %s > %s && mv -f %s %s; fi; rm -f %s ) >/dev/null 2>&1 &",
        table.concat(cmds, sep),
        table.concat(pieces, " "),
        shell_quote(part), shell_quote(part), shell_quote(path),
        table.concat(pieces, " ")))
    return path
end

-- Paths we've started playing, recorded whenever play_audio launches a clip.
-- Declared before play_audio so it's a real local (not a nil global).
local PLAYED_PATHS = {}

-- Fire and forget. The player is detached so rofi can be back on screen
-- immediately rather than waiting out the clip.
local function play_audio(path)
    if not PLAYER or not path then return false end

    -- Normally already done; only waits if Return came fast
    for _ = 1, 80 do
        if file_size(path) > 0 then break end
        os.execute("sleep 0.1")
    end
    if file_size(path) == 0 then return false end

    os.execute("setsid " .. PLAYER .. " " .. shell_quote(path) .. " >/dev/null 2>&1 &")
    PLAYED_PATHS[path] = true
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

local TRANSLATE_ENDPOINT = "https://translate.googleapis.com/translate_a/single"

-- Fetch and parse a translation. Returns { translation, roman, source }, or
-- nil + an error kind ("network" / "empty"). Uses a POST body so long inputs
-- aren't constrained by Google's ~15KB URL length limit.
local function do_translate(text, code, source)
    local sl = source and KNOWN_CODES[source] and source or "auto"
    local body = shell(string.format(
        "curl -s --max-time 12 -A %s --data-urlencode %s -d %s %s",
        shell_quote(USER_AGENT),
        shell_quote("q=" .. text),
        shell_quote("client=gtx&sl=" .. sl .. "&tl=" .. urlencode(code) .. "&dt=t&dt=rm"),
        shell_quote(TRANSLATE_ENDPOINT)))
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

    if swapped then
        -- Swapped: we're viewing the source text, so the "target" is the source language
        local src_name = t.source and source_name(t.source) or "auto"
        msg = msg .. "\n<span foreground=\"" .. COLOR_POS .. "\">" .. escape_markup(src_name) .. "</span>"
        msg = msg .. " <span foreground=\"" .. COLOR_POS .. "\">→ from " ..
            escape_markup(lang.name) .. "</span>"
    else
        -- Normal: viewing translation, target is lang, source is t.source
        msg = msg .. "\n<span foreground=\"" .. COLOR_POS .. "\">" .. escape_markup(lang.name) .. "</span>"
        if t.source then
            msg = msg .. " <span foreground=\"" .. COLOR_POS .. "\">→ from " ..
                escape_markup(source_name(t.source)) .. "</span>"
        end
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

-- One-line row for a history entry: "text → translation (lang)". Shown without
-- -markup-rows, so no markup escaping (that would print "&amp;" literally).
local function history_row(e)
    local lang = source_name(e.code)
    local t = truncate((e.text or ""):gsub("\n", " "), 45)
    local trans = truncate((e.translation or ""):gsub("\n", " "), 45)
    return t .. "  →  " .. trans .. "  (" .. lang .. ")"
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

    local sl = source and KNOWN_CODES[source] and source or "auto"
    print("### endpoint: " .. TRANSLATE_ENDPOINT .. " ###")
    print("### sl: " .. sl .. " tl: " .. code .. " (POST, q= text) ###")
    local body = shell(string.format(
        "curl -s --max-time 12 -A %s --data-urlencode %s -d %s %s",
        shell_quote(USER_AGENT),
        shell_quote("q=" .. text),
        shell_quote("client=gtx&sl=" .. sl .. "&tl=" .. urlencode(code) .. "&dt=t&dt=rm"),
        shell_quote(TRANSLATE_ENDPOINT)))
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

-- Stop every clip we started (they run detached in their own sessions).
local function stop_audio()
    for p in pairs(PLAYED_PATHS) do
        os.execute("pkill -f " .. shell_quote(p) .. " >/dev/null 2>&1")
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

        -- Left the results for this text (back / escape / re-pick): silence it.
        stop_audio()

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

stop_audio()
