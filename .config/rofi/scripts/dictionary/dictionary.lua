#!/usr/bin/env lua

-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

local HOME = os.getenv("HOME")

-- Resolve our own directory so the tree can live anywhere.
local DIR = (arg[0] or debug.getinfo(1, "S").source:match("^@(.+)$") or ""):match("^(.*)/") or "."
if DIR == "." then DIR = os.getenv("PWD") or "."
elseif DIR:sub(1, 1) ~= "/" then DIR = (os.getenv("PWD") or ".") .. "/" .. DIR end

local ROFI_THEME_INPUT = DIR .. "/dictionary.rasi"
local ROFI_THEME_SELECT = DIR .. "/select.rasi"
local ROFI_THEME_RESULTS = DIR .. "/dictionary-output.rasi"
local MAX_LINE_LENGTH = 96
local MAX_DEFS_PER_POS = 2
local MAX_LINES = 20
local MAX_SYNONYMS = 6
local CACHE = os.getenv("XDG_CACHE_HOME") or HOME .. "/.cache"
local HISTORY_FILE = CACHE .. "/dict-history"
local MAX_HISTORY = 100

-- Accents we prefer to hear, best first
local ACCENT_PREFERENCE = { "US", "UK", "AU" }

-- Wikimedia asks API clients to identify themselves; a default curl
-- User-Agent gets throttled under any real usage
local USER_AGENT = "rofi-dict/1.0 (https://github.com/kbuckleys/)"

local COLOR_HEAD = "#9bbfbf"
local COLOR_KEY = "#a2a8bc"
local COLOR_POS = "#6a707f"
local COLOR_EX = "#eebebe"
local COLOR_ERROR = "#e78284"
local ICON_HEAD = "\u{f405}"
local ICON_AUDIO = "\u{f07c5}"
local ICON_CORRECTED = "\u{f040}"

-- JSON parsing
local json = require("cjson")

-- Percent-encode for use in a URL path segment or query value.
-- Spaces become %20 — never "+", which MediaWiki's REST paths reject.
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

-- Load history entries (most recent first), one word per line
local function load_history()
    local content = read_file(HISTORY_FILE)
    local list = {}
    for line in content:gmatch("[^\n]+") do
        list[#list + 1] = line
    end
    return list
end

-- Save history entries, truncated to MAX_HISTORY
local function save_history(list)
    shell("mkdir -p " .. shell_quote(CACHE))
    local lines = {}
    for i = 1, math.min(#list, MAX_HISTORY) do
        lines[#lines + 1] = list[i]
    end
    local content = #lines > 0 and (table.concat(lines, "\n") .. "\n") or ""
    write_file(HISTORY_FILE, content)
end

-- Drop a single entry from history, matched case-insensitively
local function remove_from_history(word)
    local lower = trim(word):lower()
    if lower == "" then return end
    local kept = {}
    for _, w in ipairs(load_history()) do
        if w:lower() ~= lower then
            kept[#kept + 1] = w
        end
    end
    save_history(kept)
end

-- Add a word to the front of history, de-duplicating case-insensitively
local function add_to_history(word)
    local list = load_history()
    local lower = word:lower()
    local filtered = {}
    for _, w in ipairs(list) do
        if w:lower() ~= lower then
            filtered[#filtered + 1] = w
        end
    end
    table.insert(filtered, 1, word)
    save_history(filtered)
end

-- HTML entity decoding
local function decode_html(s)
    s = s:gsub("&nbsp;", " ")
    s = s:gsub("&amp;", "&")
    s = s:gsub("&lt;", "<")
    s = s:gsub("&gt;", ">")
    s = s:gsub("&quot;", '"')
    s = s:gsub("&#39;", "'")
    s = s:gsub("&apos;", "'")
    return s
end

-- Escape for rofi markup
local function escape_markup(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    return s
end

-- Check if string has alphanumeric content
local function has_content(s)
    return s:match("[%w]") ~= nil
end

-- Length/substring that count UTF-8 characters and degrade to bytes on any
-- invalid input, so a mid-sequence cut can never corrupt a character. Matches
-- translate.lua's helpers so both scripts wrap text identically.
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

-- Simple word wrap, UTF-8 char-aware so multi-byte characters are never split.
-- An unbroken run (URL, long word) is cut at the limit without dropping a char.
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
                lines[#lines + 1] = usub(line, 1, break_at - 1)
                line = usub(line, break_at + 1)
            else
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

--------------------------------------------------------------------------------
-- Wikitext parsing
--------------------------------------------------------------------------------

-- Return the inner text of the template starting at position 1 of s, or nil.
-- Brace-aware, so nested templates don't truncate the match.
local function template_inner(s)
    if s:sub(1, 2) ~= "{{" then return nil end
    local depth, i, n = 0, 1, #s
    while i <= n do
        local two = s:sub(i, i + 1)
        if two == "{{" then
            depth = depth + 1
            i = i + 2
        elseif two == "}}" then
            depth = depth - 1
            i = i + 2
            if depth == 0 then return s:sub(3, i - 3) end
        else
            i = i + 1
        end
    end
    return nil
end

-- Split template arguments on "|", ignoring pipes nested in {{ }} or [[ ]]
local function split_args(inner)
    local parts, cur, depth, i = {}, {}, 0, 1
    while i <= #inner do
        local two = inner:sub(i, i + 1)
        local c = inner:sub(i, i)
        if two == "{{" or two == "[[" then
            depth = depth + 1
            cur[#cur + 1] = two
            i = i + 2
        elseif two == "}}" or two == "]]" then
            depth = depth - 1
            cur[#cur + 1] = two
            i = i + 2
        elseif c == "|" and depth <= 0 then
            parts[#parts + 1] = table.concat(cur)
            cur = {}
            i = i + 1
        else
            cur[#cur + 1] = c
            i = i + 1
        end
    end
    parts[#parts + 1] = table.concat(cur)
    return parts
end

-- Positional (unnamed) arguments of a template, lang code dropped
local function positional_args(parts)
    local pos = {}
    for i = 2, #parts do
        if not parts[i]:match("^%s*[%w%-%s]+=") then
            pos[#pos + 1] = trim(parts[i])
        end
    end
    if pos[1] == "en" then table.remove(pos, 1) end
    return pos
end

-- Named argument lookup, e.g. named(parts, "a") for {{audio|en|f.ogg|a=US}}
local function named_arg(parts, key)
    for i = 2, #parts do
        local k, v = parts[i]:match("^%s*([%w%-]+)%s*=(.*)$")
        if k and k:lower() == key then return trim(v) end
    end
    return nil
end

local function template_name(parts)
    return trim(parts[1] or ""):lower()
end

-- Replace a single template with the text it should contribute
local function render_template(inner)
    local parts = split_args(inner)
    local name = template_name(parts)
    local pos = positional_args(parts)

    -- Templates that stand in for a word: show the target, not a trailing gloss
    -- ({{l|en|word|gloss}} links the word; the gloss is only disambiguation).
    if name == "w" or name == "l" or name == "m" or name == "ll"
        or name == "link" or name == "mention" or name == "glossary" then
        return pos[1] or ""
    end
    -- Non-gloss definitions and glosses: keep the prose
    if name == "n-g" or name == "ngd" or name == "non-gloss"
        or name == "non-gloss definition" or name == "gloss" or name == "gl" then
        return pos[#pos] or ""
    end
    -- Inline qualifiers render parenthesised, as they do on the site
    if name == "q" or name == "qualifier" or name == "qual" or name == "i" then
        return #pos > 0 and ("(" .. table.concat(pos, ", ") .. ")") or ""
    end
    -- Everything else (quotes, references, categories) contributes nothing
    return ""
end

-- Reduce wikitext markup to plain prose
local function strip_wikitext(s)
    if not s or s == "" then return "" end

    s = s:gsub("<ref[^>]*/>", "")
    s = s:gsub("<ref[^>]*>.-</ref>", "")

    -- Innermost-first so nested templates resolve correctly
    for _ = 1, 8 do
        local new, n = s:gsub("%{%{([^{}]*)%}%}", render_template)
        s = new
        if n == 0 then break end
    end
    s = s:gsub("%{%{", ""):gsub("%}%}", "")

    s = s:gsub("%[%[[^%[%]|]*|([^%[%]|]*)%]%]", "%1")
    s = s:gsub("%[%[([^%[%]]*)%]%]", "%1")
    s = s:gsub("%[https?://%S+%s+([^%]]*)%]", "%1")
    s = s:gsub("%[https?://%S+%]", "")

    s = s:gsub("'''''", ""):gsub("'''", ""):gsub("''", "")
    s = s:gsub("<[^>]*>", "")

    s = decode_html(s)
    s = s:gsub("%s+", " ")
    -- Tidy space left behind by dropped templates
    s = s:gsub("%s+([,;.!?])", "%1")
    s = s:gsub("^[%s,;:]+", "")
    return trim(s)
end

-- Slice out the ==English== section; Wiktionary pages hold many languages
local function english_section(wikitext)
    local out, in_en = {}, false
    for line in (wikitext .. "\n"):gmatch("([^\n]*)\n") do
        local heading = line:match("^==%s*([^=]+)%s*==%s*$")
        if heading then
            in_en = (trim(heading):lower() == "english")
        elseif in_en then
            out[#out + 1] = line
        end
    end
    return table.concat(out, "\n")
end

local POS_HEADINGS = {
    ["noun"] = true, ["proper noun"] = true, ["verb"] = true, ["adjective"] = true,
    ["adverb"] = true, ["preposition"] = true, ["conjunction"] = true,
    ["interjection"] = true, ["pronoun"] = true, ["determiner"] = true,
    ["numeral"] = true, ["number"] = true, ["article"] = true, ["particle"] = true,
    ["phrase"] = true, ["proverb"] = true, ["prepositional phrase"] = true,
    ["verb phrase"] = true, ["adjective phrase"] = true, ["adverbial phrase"] = true,
    ["contraction"] = true, ["idiom"] = true, ["abbreviation"] = true,
    ["acronym"] = true, ["initialism"] = true, ["prefix"] = true, ["suffix"] = true,
}

-- Pull a leading {{lb|en|...}} off a definition line.
-- Returns label text (or nil) and the remaining line.
local function extract_label(line)
    local lead = line:match("^%s*(%{%{.*)$")
    if not lead then return nil, line end
    local inner = template_inner(lead)
    if not inner then return nil, line end

    local parts = split_args(inner)
    local name = template_name(parts)
    if name ~= "lb" and name ~= "label" and name ~= "lbl" and name ~= "tlb" then
        return nil, line
    end

    local labels = {}
    for _, p in ipairs(positional_args(parts)) do
        -- "_", "and", "or" are Wiktionary's label connectors, not labels
        if p ~= "" and p ~= "_" and p ~= "and" and p ~= "or" then
            labels[#labels + 1] = p
        end
    end

    local rest = lead:sub(#inner + 5)
    if #labels == 0 then return nil, rest end
    return table.concat(labels, ", "), rest
end

-- Classify a recording by filename prefix (En-us-…), falling back to |a=
local function audio_accent(file, annotation)
    local prefix = file:lower():match("^en%-(%a+)%-")
    if prefix then return prefix:upper() end
    if annotation and annotation ~= "" then
        local a = annotation:lower():gsub("[^%a]", "")
        if a == "us" or a == "ga" or a == "genam" or a == "america"
            or a == "american" or a == "generalamerican" then return "US" end
        if a == "uk" or a == "rp" or a == "british" or a == "britain"
            or a == "england" or a == "receivedpronunciation" then return "UK" end
        if a == "au" or a == "aus" or a == "australia"
            or a == "australian" then return "AU" end
    end
    return nil
end

local function accent_rank(code)
    for i, want in ipairs(ACCENT_PREFERENCE) do
        if code == want then return i end
    end
    return code and (#ACCENT_PREFERENCE + 1) or (#ACCENT_PREFERENCE + 2)
end

local AUDIO_EXT = { ogg = true, oga = true, mp3 = true, wav = true, flac = true }

-- Parse the English section into a structured entry
local function parse_entry(wikitext)
    local section = english_section(wikitext)
    if section == "" then return nil end

    local entry = {
        pos_order = {},
        grouped = {},
        ipa = nil,
        audio = nil,
        synonyms = {},
    }

    local current_pos, def_count = nil, 0
    local in_synonyms = false
    local last_def = nil
    local ipa_candidates, audio_candidates = {}, {}
    local seen_syn = {}

    local function add_synonyms(list)
        for _, s in ipairs(list) do
            -- A "Synonyms" bullet holds several {{l|en|…}} in one line, so the
            -- stripped result is comma-joined; split it back into terms.
            for term in (strip_wikitext(s) .. ","):gmatch("([^,;]*)[,;]") do
                local clean = trim(term)
                -- Thesaurus cross-links aren't usable synonyms, and "see also …"
                -- survives template stripping, so match anywhere in the string
                if clean ~= "" and not clean:find("Thesaurus:", 1, true)
                    and not seen_syn[clean:lower()] then
                    seen_syn[clean:lower()] = true
                    entry.synonyms[#entry.synonyms + 1] = clean
                end
            end
        end
    end

    for line in (section .. "\n"):gmatch("([^\n]*)\n") do
        local hashes, heading = line:match("^(=+)%s*(.-)%s*=+%s*$")
        if hashes and #hashes >= 3 then
            local h = heading:lower():gsub("%s*%d+%s*$", "")
            in_synonyms = (h == "synonyms")
            if POS_HEADINGS[h] then
                current_pos = h
                def_count = 0
                if not entry.grouped[h] then
                    entry.grouped[h] = {}
                    entry.pos_order[#entry.pos_order + 1] = h
                end
            else
                current_pos = nil
            end
            last_def = nil
        else
            -- Pronunciation data can appear anywhere in the section
            local ipa_at = line:find("%{%{%s*IPA%s*|")
            if ipa_at then
                local inner = template_inner(line:sub(ipa_at))
                if inner then
                    local parts = split_args(inner)
                    for _, v in ipairs(positional_args(parts)) do
                        if v:match("^[/%[]") then
                            ipa_candidates[#ipa_candidates + 1] =
                                { text = v, accent = named_arg(parts, "a") }
                        end
                    end
                end
            end

            local audio_at = line:find("%{%{%s*[Aa]udio%s*|")
            if audio_at then
                local inner = template_inner(line:sub(audio_at))
                if inner then
                    local parts = split_args(inner)
                    for _, v in ipairs(positional_args(parts)) do
                        local ext = v:match("%.(%a+)$")
                        if ext and AUDIO_EXT[ext:lower()] then
                            audio_candidates[#audio_candidates + 1] =
                                { file = v, code = audio_accent(v, named_arg(parts, "a")) }
                        end
                    end
                end
            end

            if in_synonyms then
                local bullet = line:match("^%*+%s*(.*)$")
                if bullet and bullet ~= "" then
                    add_synonyms(split_args(bullet))
                end
            end

            local body = line:match("^#([^#:*].*)$")
            if body and current_pos and def_count < MAX_DEFS_PER_POS then
                local label, rest = extract_label(body)
                local text = strip_wikitext(rest)
                if has_content(text) then
                    def_count = def_count + 1
                    last_def = { def = text, label = label, ex = "" }
                    local g = entry.grouped[current_pos]
                    g[#g + 1] = last_def
                end
            elseif line:match("^#:") then
                local sub = trim(line:match("^#:%s*(.*)$") or "")
                local inner = template_inner(sub)
                local name = inner and template_name(split_args(inner)) or nil
                if name == "syn" or name == "synonyms" then
                    add_synonyms(positional_args(split_args(inner)))
                elseif last_def and last_def.ex == "" then
                    -- {{ux|en|…}} and friends, or a bare inline example
                    local text
                    if name == "ux" or name == "usex" or name == "uxi" or name == "ux+" then
                        text = strip_wikitext(positional_args(split_args(inner))[1] or "")
                    elseif name ~= "ant" and name ~= "antonyms" then
                        text = strip_wikitext(sub)
                    end
                    if text and has_content(text) then
                        last_def.ex = text
                    end
                end
            end
        end
    end

    -- Prefer an IPA matching our top accent, else the first listed
    table.sort(ipa_candidates, function(a, b)
        return accent_rank(audio_accent("", a.accent)) < accent_rank(audio_accent("", b.accent))
    end)
    if ipa_candidates[1] then entry.ipa = ipa_candidates[1].text end

    table.sort(audio_candidates, function(a, b)
        return accent_rank(a.code) < accent_rank(b.code)
    end)
    if audio_candidates[1] then entry.audio = audio_candidates[1] end

    while #entry.synonyms > MAX_SYNONYMS do
        table.remove(entry.synonyms)
    end

    -- An entry with headings but no definitions is not a usable result
    for _, pos in ipairs(entry.pos_order) do
        if #entry.grouped[pos] > 0 then return entry end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Network
--------------------------------------------------------------------------------

local function fetch_wikitext(title)
    -- redirects=1 matters: many idioms are redirects, e.g.
    -- "cost an arm and a leg" -> "an arm and a leg"
    local url = "https://en.wiktionary.org/w/api.php?action=parse&page="
        .. urlencode(title) .. "&prop=wikitext&format=json&formatversion=2&redirects=1"
    local body = shell(string.format("curl -s --max-time 8 -A %s %s",
        shell_quote(USER_AGENT), shell_quote(url)))
    if not body or body == "" then return nil, "network" end

    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= "table" then return nil, "network" end
    if data.error then return nil, "missing" end
    if not data.parse or not data.parse.wikitext then return nil, "missing" end
    return data.parse.wikitext, nil, data.parse.title
end

-- Wiktionary's own search. It is fuzzy enough to absorb real typos:
-- "run off the mill" -> "run-of-the-mill", "kick the buckit" -> "kick the bucket",
-- "peice of cake" -> "piece of cake". Returns up to `limit` candidates, best first.
local function suggest(term, limit)
    limit = limit or 3
    local url = "https://en.wiktionary.org/w/api.php?action=opensearch&search="
        .. urlencode(term) .. "&limit=" .. limit .. "&format=json"
    local body = shell(string.format("curl -s --max-time 6 -A %s %s",
        shell_quote(USER_AGENT), shell_quote(url)))
    if not body or body == "" then return {} end
    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= "table" then return {} end
    local list = data[2]
    if type(list) ~= "table" then return {} end

    local out = {}
    for i = 1, math.min(#list, limit) do out[#out + 1] = list[i] end
    return out
end

-- Resolve a query to an entry. Tries the word as typed, then lowercased
-- (page titles are case-sensitive, so "UBIQUITOUS" needs a second go), then
-- Wiktionary's search for typos.
-- Returns entry, resolved title, corrected (bool), error kind
local function resolve(word)
    local tried = {}

    -- Only a genuinely different headword counts as a correction; matching a
    -- page that differs from the query in case alone is not worth flagging
    local function attempt(candidate)
        -- Keyed on the exact string: page titles are case-sensitive, so the
        -- lowercased retry is a genuinely different fetch, not a duplicate
        if tried[candidate] then return nil end
        tried[candidate] = true

        local wikitext, err, title = fetch_wikitext(candidate)
        if wikitext then
            local entry = parse_entry(wikitext)
            if entry then
                local resolved = title or candidate
                return entry, resolved, resolved:lower() ~= word:lower()
            end
        elseif err == "network" then
            return nil, nil, nil, "network"
        end
        return nil
    end

    local candidates = { word }
    if word:lower() ~= word then candidates[#candidates + 1] = word:lower() end

    for _, c in ipairs(candidates) do
        local entry, title, corrected, err = attempt(c)
        if entry then return entry, title, corrected, nil end
        if err == "network" then return nil, word, false, "network" end
    end

    for _, c in ipairs(suggest(word, 3)) do
        local entry, title, corrected, err = attempt(c)
        if entry then return entry, title, corrected, nil end
        if err == "network" then return nil, word, false, "network" end
    end

    return nil, word, false, "missing"
end

--------------------------------------------------------------------------------
-- Audio
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

local function file_size(path)
    local f = io.open(path, "r")
    if not f then return 0 end
    local size = f:seek("end")
    f:close()
    return size
end

-- Start the download while the user is still reading the definition, so
-- pressing Space doesn't stall on the network. Downloads to a .part file and
-- renames, so a half-written file is never played. Returns the temp path.
local function prefetch_audio(file)
    if not PLAYER or not file then return nil end

    local path = os.tmpname()
    local part = path .. ".part"
    local url = "https://commons.wikimedia.org/wiki/Special:FilePath/" .. urlencode(file)
    os.execute(string.format(
        "( curl -sL --max-time 10 -A %s %s -o %s && mv -f %s %s ) >/dev/null 2>&1 &",
        shell_quote(USER_AGENT), shell_quote(url),
        shell_quote(part), shell_quote(part), shell_quote(path)))
    return path
end

-- Fire and forget. The player is detached so rofi can be back on screen
-- immediately rather than waiting out the clip.
local function play_audio(path)
    if not PLAYER or not path then return false end

    -- Normally already done; only waits if Space came fast
    for _ = 1, 20 do
        if file_size(path) > 0 then break end
        os.execute("sleep 0.1")
    end
    if file_size(path) == 0 then return false end

    os.execute("setsid " .. PLAYER .. " " .. shell_quote(path) .. " >/dev/null 2>&1 &")
    return true
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

-- A small "key action <sep> key action" row for the bottom of the message bar.
-- Keys are bold COLOR_KEY; descriptions are the dim COLOR_POS. Key names are
-- spelled out rather than drawn as symbol glyphs, which are not all guaranteed
-- to exist in the configured Nerd Font.
local function hint_row(bindings)
    local parts = {}
    for _, b in ipairs(bindings) do
        parts[#parts + 1] = "<b><span foreground=\"" .. COLOR_KEY .. "\">" ..
            b[1] .. "</span></b> <span foreground=\"" .. COLOR_POS .. "\">" ..
            b[2] .. "</span>"
    end
    return "<span size=\"small\">" ..
        table.concat(parts, "    ") .. "</span>"
end

-- Build the header shown above the definition list
local function build_message(word, entry, suggested)
    local msg = "<span foreground=\"" .. COLOR_HEAD .. "\">" .. ICON_HEAD .. "</span>  " ..
        "<b><span foreground=\"" .. COLOR_HEAD .. "\">" .. escape_markup(word) .. "</span></b>"
    if entry.ipa and entry.ipa ~= "" then
        msg = msg .. "  <span foreground=\"" .. COLOR_HEAD .. "\">" ..
            escape_markup(entry.ipa) .. "</span>"
    end
    if entry.audio and PLAYER then
        local tag = entry.audio.code and (" " .. entry.audio.code) or ""
        msg = msg .. "  <span foreground=\"" .. COLOR_HEAD .. "\">" ..
            ICON_AUDIO .. escape_markup(tag) .. "</span>"
    end
    if suggested then
        msg = msg .. "  <span foreground=\"" .. COLOR_POS .. "\"><i>" ..
            ICON_CORRECTED .. " CORRECTED</i></span>"
    end

    local keys = {}
    if entry.audio and PLAYER then
        keys[#keys + 1] = { "return/space", "play" }
    end
    keys[#keys + 1] = { "backspace", "back" }
    keys[#keys + 1] = { "esc", "close" }

    return msg .. "\n" .. hint_row(keys)
end

-- Build the definition list body
local function build_lines(entry)
    local lines = {}

    local function add_blank()
        if #lines > 0 and lines[#lines] ~= "" then
            lines[#lines + 1] = ""
        end
    end

    for _, pos in ipairs(entry.pos_order) do
        local defs = entry.grouped[pos]
        if #defs > 0 then
            add_blank()
            lines[#lines + 1] = "<span foreground=\"" .. COLOR_POS .. "\"><i>" ..
                escape_markup(pos) .. "</i></span>"

            for _, d in ipairs(defs) do
                local label = d.label and ("(" .. d.label .. ")") or nil
                local plain = label and (label .. " " .. d.def) or d.def

                for i, wline in ipairs(wrap(plain, MAX_LINE_LENGTH)) do
                    local esc = escape_markup(wline)
                    if i == 1 and label then
                        local elab = escape_markup(label)
                        if esc:sub(1, #elab) == elab then
                            esc = "<span foreground=\"" .. COLOR_POS .. "\"><i>" ..
                                elab .. "</i></span>" .. esc:sub(#elab + 1)
                        end
                    end
                    lines[#lines + 1] = "  " .. esc
                end

                if has_content(d.ex) then
                    for _, wline in ipairs(wrap(d.ex, MAX_LINE_LENGTH)) do
                        lines[#lines + 1] = "  <span foreground=\"" .. COLOR_EX .. "\"><i>" ..
                            escape_markup(wline) .. "</i></span>"
                    end
                    lines[#lines + 1] = ""
                end
            end
        end
    end

    if #entry.synonyms > 0 then
        add_blank()
        lines[#lines + 1] = "<span foreground=\"" .. COLOR_HEAD .. "\"><b>Synonyms:</b> " ..
            escape_markup(table.concat(entry.synonyms, ", ")) .. "</span>"
    end

    while #lines > 0 and lines[#lines] == "" do
        lines[#lines] = nil
    end

    return lines
end

-- Run rofi over `input_file`, returning its exit code and the selected line.
-- rofi prints the highlighted entry on custom keybindings too, which is what
-- makes Delete-to-forget work on the history list.
local function run_rofi(args, input_file)
    local outfile = os.tmpname()
    local cmd = string.format("rofi %s < %s > %s 2>/dev/null",
        args, shell_quote(input_file), shell_quote(outfile))

    local ok, _, code = os.execute(cmd)
    local out = read_file(outfile)
    remove_file(outfile)

    return code or 0, trim(out)
end

-- Show the results screen. Returns rofi's exit code:
--   0  Return      play pronunciation
--   10 Space       play pronunciation
--   11 BackSpace   back to the input prompt
--   1  Escape      back to the input prompt
local function show_results(lines, message, audio_enabled)
    local tmpfile = os.tmpname()
    write_file(tmpfile, #lines > 0 and (table.concat(lines, "\n") .. "\n") or "\n")

    -- BackSpace ships bound to kb-remove-char-back; leaving that in place makes
    -- it a double binding and rofi rejects it. Nothing is typed on this screen,
    -- so dropping the editing key costs nothing.
    local binds = ' -kb-remove-char-back "" -kb-custom-2 "BackSpace"'
    if audio_enabled then
        binds = binds .. ' -kb-custom-1 "space"'
    end

    local n_lines = math.max(1, math.min(#lines, MAX_LINES))
    local args = string.format(
        '-dmenu -wayland-layer top -theme %s -no-sort -lines %d -p "Definition" -markup-rows%s%s',
        shell_quote(ROFI_THEME_RESULTS),
        n_lines,
        message ~= "" and (" -mesg " .. shell_quote(message)) or "",
        binds
    )

    local code = run_rofi(args, tmpfile)
    remove_file(tmpfile)
    return code
end

local function show_error(text)
    local msg = "<span foreground=\"" .. COLOR_ERROR .. "\">" .. escape_markup(text) .. "</span>"
    show_results({ msg }, "", false)
end

--------------------------------------------------------------------------------
-- Debug mode
--------------------------------------------------------------------------------

if arg[1] == "--debug" then
    local word = arg[2]
    if not word then
        io.stderr:write("usage: dictionary.lua --debug <word>\n")
        os.exit(1)
    end

    print("### query: " .. word .. " ###")
    print("### opensearch: " .. table.concat(suggest(word, 3), " | ") .. " ###")

    -- Go through resolve() rather than re-implementing it, so debug output
    -- reflects the same case-folding and typo fallbacks the real run uses
    local entry, title, corrected, err = resolve(word)
    if not entry then
        print("### unresolved (" .. tostring(err) .. ") ###")
        os.exit(1)
    end

    print("### resolved title: " .. tostring(title) .. " ###")
    print("### corrected: " .. tostring(corrected) .. " ###")

    local wikitext = fetch_wikitext(title)
    if wikitext then
        local section = english_section(wikitext)
        print("### english section: " .. #section .. " bytes of " .. #wikitext .. " ###")
        print(section:sub(1, 1500))
    end

    print("### ipa: " .. tostring(entry.ipa) .. " ###")
    if entry.audio then
        print("### audio: " .. entry.audio.file .. "  accent=" .. tostring(entry.audio.code) .. " ###")
    else
        print("### audio: none ###")
    end
    print("### synonyms: " .. table.concat(entry.synonyms, ", ") .. " ###")
    print("### player: " .. tostring(PLAYER) .. " ###")

    print("### definitions ###")
    for _, pos in ipairs(entry.pos_order) do
        for _, d in ipairs(entry.grouped[pos]) do
            print(string.format("[%s] %s%s", pos,
                d.label and ("(" .. d.label .. ") ") or "", d.def))
            if has_content(d.ex) then print("    ex: " .. d.ex) end
        end
    end

    print("### rendered ###")
    print(build_message(title or word, entry, corrected))
    for _, l in ipairs(build_lines(entry)) do print(l) end

    os.exit(0)
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

-- Marker returned by prompt_for_word() when the user confirms an empty box,
-- meaning "show the lookup history" instead of quitting.
local HISTORY_MARKER = { history = true }

-- Show the input prompt. An empty confirmation opens the lookup history
-- instead of quitting. Returns the word to look up, the history marker, or
-- nil to quit.
local function prompt_for_word()
    local empty = os.tmpname()
    write_file(empty, "")

    local mesg = "<span foreground=\"" .. COLOR_HEAD .. "\">" .. ICON_HEAD .. "</span>" ..
        "\n" .. hint_row({ { "return", "define / history" }, { "esc", "quit" } })
    local args = string.format(
        '-dmenu -wayland-layer top -theme %s -p "Define" -mesg %s -no-sort',
        shell_quote(ROFI_THEME_INPUT), shell_quote(mesg))

    local code, out = run_rofi(args, empty)
    remove_file(empty)

    if code ~= 0 then return nil end
    out = trim(out)
    if out == "" then return HISTORY_MARKER end
    return out
end

-- Pick a word from the lookup history. Delete removes the highlighted entry
-- and refreshes. Returns the word to re-look up, or nil to go back.
local function show_history()
    while true do
        local history = load_history()
        if #history == 0 then return nil end

        local hist_file = os.tmpname()
        write_file(hist_file, table.concat(history, "\n") .. "\n")

        -- Delete is bound by default to both kb-delete-entry and
        -- kb-remove-char-forward; leaving either in place makes a double binding
        -- and rofi rejects it. Rebind to a custom key so we can persist.
        local binds = ' -kb-delete-entry "" -kb-remove-char-forward "" -kb-custom-1 "Delete"'
        local mesg = hint_row({
            { "return", "re-look up" }, { "delete", "remove" }, { "esc", "back" }
        })
        local args = string.format(
            '-dmenu -i -no-custom -wayland-layer top -theme %s -no-sort -p "History" -mesg %s%s',
            shell_quote(ROFI_THEME_SELECT), shell_quote(mesg), binds)

        local code, out = run_rofi(args, hist_file)
        remove_file(hist_file)

        if code == 0 then
            for i, h in ipairs(history) do
                if out == h then return h end
            end
            return nil
        elseif code == 10 then
            for i, h in ipairs(history) do
                if out == h then
                    remove_from_history(h)
                    break
                end
            end
        else
            return nil
        end
    end
end

-- Resolve `word` and show its definition, with pronunciation. Records the
-- resolved title in history and keeps the results screen replayable.
local function lookup(word)
    local entry, title, suggested, err = resolve(word)

    if err == "network" then
        show_error("Network error — couldn't reach Wiktionary")
        return
    elseif not entry then
        show_error("No definitions found for \"" .. word .. "\". Check spelling?")
        return
    end

    add_to_history(title)

    local message = build_message(title, entry, suggested)
    local lines = build_lines(entry)
    local audio_enabled = (entry.audio ~= nil) and (PLAYER ~= nil)

    -- Download now, while the definition is still being read, so Space
    -- doesn't wait on the network
    local audio_path = audio_enabled and prefetch_audio(entry.audio.file) or nil

    -- rofi always exits on a keybinding, so playing means: hand the clip to
    -- a detached player and reopen immediately. Playback overlaps the
    -- restored menu instead of the menu waiting for the clip to end.
    -- Backspace and Escape fall through to the input prompt.
    local replay
    repeat
        local code = show_results(lines, message, audio_enabled)
        replay = (code == 0 or code == 10) and audio_path ~= nil
        if replay then play_audio(audio_path) end
    until not replay

    if audio_path then
        remove_file(audio_path)
        remove_file(audio_path .. ".part")
    end
end

while true do
    local word = prompt_for_word()
    if not word then break end

    if word.history then
        -- Empty box: offer saved words instead of quitting.
        word = show_history()
    end
    if word then lookup(word) end
end
