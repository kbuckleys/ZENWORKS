#!/usr/bin/env lua

-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- Change your opener and description here
local DIR_OPENER = "kitty -1 yazi"
local DIR_OPENER_LABEL = "open in yazi"

local HOME = os.getenv("HOME")

local DIR = (arg[0] or debug.getinfo(1, "S").source:match("^@(.+)$") or ""):match("^(.*)/") or "."
if DIR == "." then DIR = os.getenv("PWD") or "."
elseif DIR:sub(1, 1) ~= "/" then DIR = (os.getenv("PWD") or ".") .. "/" .. DIR end
local SELF = DIR .. "/fatman.lua"
local CONFIG = DIR .. "/fatman.rasi"
local THEME = DIR .. "/fatman.rasi"
local ICONS = DIR .. "/icons.lua"

local CACHE = os.getenv("XDG_CACHE_HOME") or HOME .. "/.cache"
local STATE = CACHE .. "/rofi-fatman.state"
local BS_DIR = CACHE .. "/rofi-fatman-bs"

local OPENER = "xdg-open"
local CLEAR_BS = true
local SEARCH_THEME = DIR .. "/fatsearch.rasi"
local SEARCH_CONFIG = DIR .. "/config.rasi"
local OPENED_SENTINEL = "/tmp/rofi-fatman-opened"
local ESC_SENTINEL = "/tmp/rofi-fatman-escaped"

local BIND_KEY_COLOR = "#a2a8bc"
local BIND_ACT_COLOR = "#6a707f"

-- Render {key, action} pairs as a pango hint line. Attribute values are single
-- quoted so the result can also be embedded in a double-quoted rasi string.
local function binds(...)
    local out = {}
    for _, kv in ipairs({ ... }) do
        out[#out + 1] = "<b><span foreground='" .. BIND_KEY_COLOR .. "'>" .. kv[1] .. "</span></b>"
            .. " <span foreground='" .. BIND_ACT_COLOR .. "'>" .. kv[2] .. "</span>"
    end
    -- One size down: keeps the longer browse hint on a single 700px line and
    -- sets it below the path/directory line above it.
    return "<span size='smaller'>" .. table.concat(out, "    ") .. "</span>"
end

local BROWSE_BINDS = binds({ "return", "open" }, { "shift return", DIR_OPENER_LABEL },
    { "backspace", "up" }, { "tab", "search" })
local SEARCH_BINDS = binds({ "return", "open" }, { "tab", "filemanager" }, { "esc", "close" })

local function shell_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function pango_escape(s)
    return (s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function strip_markup(s)
    s = s:gsub('^<span foreground="#[0-9a-fA-F]+">[^<]*</span> ', "")
    s = s:gsub("<[^>]*>", "")
    return s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read("*a"); f:close()
    return trim(data)
end

local function write_file(path, data)
    local f = io.open(path, "w")
    if f then f:write(data, "\n"); f:close() end
end

local function shell(cmd)
    local p = io.popen(cmd)
    if not p then return nil end
    local out = p:read("*a"); p:close()
    return trim(out)
end

local function get_own_pid()
    local f = io.open("/proc/self/stat")
    local raw = f and f:read("*a")
    if f then f:close() end
    return raw and tonumber(raw:match("^(%d+)"))
end

local function proc_alive(pid)
    if not pid or pid == "" then return true end
    local f = io.open("/proc/" .. pid .. "/stat")
    if not f then return false end
    f:close()
    return true
end

local function parent_dir(p)
    if p == "/" then return "/" end
    local par = p:match("^(.*)/[^/]*$")
    if not par or par == "" then return "/" end
    return par
end

local function resolve(p)
    local f = io.popen("realpath " .. shell_quote(p) .. " 2>/dev/null")
    if not f then return p end
    local out = trim(f:read("*a")); f:close()
    if out ~= "" then return out end
    return p
end

local function is_dir(p)
    return os.execute("test -d " .. shell_quote(p)) == true
end

local function is_file(p)
    return os.execute("test -f " .. shell_quote(p)) == true
end

local function open_path(p)
    os.execute(OPENER .. " " .. shell_quote(p) .. " >/dev/null 2>&1 &")
end

local function open_dir(p)
    os.execute(DIR_OPENER .. " " .. shell_quote(p) .. " >/dev/null 2>&1 &")
end

-- ── Backspace monitor ─────────────────────────────────────────────────
-- Backspace is ambiguous: rofi edits the filter natively, but on an empty
-- filter the press is swallowed by its keyboard grab. A C helper forwards
-- raw EV_KEY events over a fifo; the --bsmon process shadows rofi's filter
-- and, when a Backspace arrives with the shadow empty, injects
-- Control+Shift+Delete (= kb-custom-1 = exit code 10) via uinput, falling
-- back to wtype. Ported from spoot.lua, self-contained.
local BS_C_SOURCE = [=[
#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <errno.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <linux/input.h>
#include <linux/uinput.h>

#define MAXDEV 32
#define NBITS(x) ((((x) - 1) / (8 * sizeof(unsigned long))) + 1)
#define INJ_NAME "spbsd-inject"

static int devfds[MAXDEV];
static int ndev = 0;
static int evfd = -1;
static int cmdfd = -1;
static int uifd = -1;

static void on_term(int sig) {
    (void)sig;
    _exit(0);
}

static int has_backspace(int fd) {
    unsigned long evbits[NBITS(EV_MAX)] = {0};
    if (ioctl(fd, EVIOCGBIT(0, sizeof(evbits)), evbits) < 0) return 0;
    if (!(evbits[EV_KEY / (8 * sizeof(unsigned long))]
          & (1UL << (EV_KEY % (8 * sizeof(unsigned long)))))) return 0;
    unsigned long keys[NBITS(KEY_MAX)] = {0};
    if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keys)), keys) < 0) return 0;
    return (keys[KEY_BACKSPACE / (8 * sizeof(unsigned long))]
            & (1UL << (KEY_BACKSPACE % (8 * sizeof(unsigned long))))) ? 1 : 0;
}

/* Skip our own injector device so injected keys never loop back. */
static int is_own_device(int fd) {
    char name[256];
    if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) < 0) return 0;
    name[sizeof(name) - 1] = 0;
    return strcmp(name, INJ_NAME) == 0;
}

static void setup_uinput(void) {
    uifd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (uifd < 0) {
        fprintf(stderr, "HELPER no uinput\n");
        return;
    }
    struct uinput_setup setup;
    memset(&setup, 0, sizeof(setup));
    strncpy(setup.name, INJ_NAME, sizeof(setup.name) - 1);
    setup.id.bustype = BUS_VIRTUAL;
    setup.id.vendor = 0x1234;
    setup.id.product = 0x5678;
    setup.id.version = 1;
    ioctl(uifd, UI_SET_EVBIT, EV_KEY);
    ioctl(uifd, UI_SET_KEYBIT, KEY_DELETE);
    ioctl(uifd, UI_SET_KEYBIT, KEY_LEFTCTRL);
    ioctl(uifd, UI_SET_KEYBIT, KEY_RIGHTCTRL);
    ioctl(uifd, UI_SET_KEYBIT, KEY_LEFTSHIFT);
    ioctl(uifd, UI_SET_KEYBIT, KEY_RIGHTSHIFT);
    if (ioctl(uifd, UI_DEV_SETUP, &setup) < 0
        || ioctl(uifd, UI_DEV_CREATE) < 0) {
        close(uifd);
        uifd = -1;
        return;
    }
    usleep(10000); /* let the kernel register /dev/input/eventX */
    fprintf(stderr, "HELPER uinput ready\n");
}

static void inject_back(void) {
    if (uifd < 0) return;
    struct input_event e[7];
    int n = 0;
    memset(&e[n], 0, sizeof(e[0])); e[n].type = EV_KEY; e[n].code = KEY_LEFTCTRL;  e[n].value = 1; n++;
    memset(&e[n], 0, sizeof(e[0])); e[n].type = EV_KEY; e[n].code = KEY_LEFTSHIFT; e[n].value = 1; n++;
    memset(&e[n], 0, sizeof(e[0])); e[n].type = EV_KEY; e[n].code = KEY_DELETE;     e[n].value = 1; n++;
    memset(&e[n], 0, sizeof(e[0])); e[n].type = EV_KEY; e[n].code = KEY_DELETE;     e[n].value = 0; n++;
    memset(&e[n], 0, sizeof(e[0])); e[n].type = EV_KEY; e[n].code = KEY_LEFTSHIFT; e[n].value = 0; n++;
    memset(&e[n], 0, sizeof(e[0])); e[n].type = EV_KEY; e[n].code = KEY_LEFTCTRL;  e[n].value = 0; n++;
    memset(&e[n], 0, sizeof(e[0])); e[n].type = EV_SYN; e[n].code = SYN_REPORT;    e[n].value = 0; n++;
    if (write(uifd, e, n * sizeof(struct input_event)) < 0)
        fprintf(stderr, "HELPER inject write failed\n");
    else
        fprintf(stderr, "HELPER INJECT sent\n");
}

static void open_devices(void) {
    DIR *d = opendir("/dev/input");
    if (!d) return;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (strncmp(e->d_name, "event", 5) != 0) continue;
        char path[160];
        snprintf(path, sizeof(path), "/dev/input/%s", e->d_name);
        int fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;
        if (!has_backspace(fd) || is_own_device(fd)) { close(fd); continue; }
        if (ndev < MAXDEV) {
            devfds[ndev++] = fd;
            fprintf(stderr, "HELPER open %s\n", path);
        }
        else close(fd);
    }
    closedir(d);
}

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    const char *evfifo = argv[1];
    const char *cmdfifo = argv[2];
    setup_uinput();
    open_devices();
    fprintf(stderr, "HELPER devices=%d\n", ndev);
    evfd = open(evfifo, O_WRONLY);
    if (evfd < 0) return 3;
    if (ndev == 0) {
        dprintf(evfd, "NODEV\n");
        close(evfd);
        return 4;
    }
    signal(SIGTERM, on_term);
    signal(SIGINT, on_term);
    dprintf(evfd, "READY\n");
    if (uifd < 0) dprintf(evfd, "NOUINPUT\n");
    cmdfd = open(cmdfifo, O_RDONLY | O_NONBLOCK);
    int running = 1;
    while (running) {
        fd_set rfds;
        FD_ZERO(&rfds);
        int maxfd = -1;
        for (int i = 0; i < ndev; i++) {
            FD_SET(devfds[i], &rfds);
            if (devfds[i] > maxfd) maxfd = devfds[i];
        }
        if (cmdfd >= 0) {
            FD_SET(cmdfd, &rfds);
            if (cmdfd > maxfd) maxfd = cmdfd;
        }
        if (maxfd < 0) break;
        int r = select(maxfd + 1, &rfds, NULL, NULL, NULL);
        if (r < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (cmdfd >= 0 && FD_ISSET(cmdfd, &rfds)) {
            char buf[64];
            int n = read(cmdfd, buf, sizeof(buf));
            for (int i = 0; i < n; i++) {
                if (buf[i] == '1') inject_back();
            }
        }
        for (int i = 0; i < ndev && running; i++) {
            if (!FD_ISSET(devfds[i], &rfds)) continue;
            struct input_event ev;
            int n = read(devfds[i], &ev, sizeof(ev));
            if (n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR)) {
                close(devfds[i]);
                devfds[i] = devfds[--ndev];
                i--;
                continue;
            }
            if (n < 0) continue;
            if (n < (int)sizeof(ev)) continue;
            if (ev.type != EV_KEY) continue;
            if (dprintf(evfd, "K %d %d\n", ev.code, ev.value) < 0) {
                running = 0;
                break;
            }
        }
    }
    if (uifd >= 0) {
        ioctl(uifd, UI_DEV_DESTROY);
        close(uifd);
    }
    if (evfd >= 0) close(evfd);
    if (cmdfd >= 0) close(cmdfd);
    for (int i = 0; i < ndev; i++) close(devfds[i]);
    return 0;
}
]=]

local bs_bin = nil

local function bs_compile()
    if not is_dir(BS_DIR) then
        os.execute("rm -f " .. shell_quote(BS_DIR))
    end
    os.execute("mkdir -p " .. shell_quote(BS_DIR))
    local bin = BS_DIR .. "/spbsd"
    local stamp = BS_DIR .. "/spbsd.stamp"
    local function exists(p)
        local f = io.open(p, "r")
        if f then f:close(); return true end
        return false
    end
    if (read_file(stamp) or "") ~= tostring(#BS_C_SOURCE) or not exists(bin) then
        local src = BS_DIR .. "/spbsd.c"
        write_file(src, BS_C_SOURCE)
        os.execute("gcc -O2 -w -o " .. shell_quote(bin) .. " " .. shell_quote(src) .. " 2>/dev/null")
        os.remove(src)
        write_file(stamp, tostring(#BS_C_SOURCE))
    end
    if exists(bin) then
        os.execute("chmod +x " .. shell_quote(bin))
        return bin
    end
    return nil
end

local _bs = nil
local _bs_gen = 0

local function bs_start()
    local bin = bs_compile()
    if not bin then return false end
    bs_bin = bin
    local pid = tostring(get_own_pid() or math.random(100000, 999999))
    local run = BS_DIR .. "/run_" .. pid .. "_" .. tostring(math.random(10000, 99999))
    os.execute("mkdir -p " .. shell_quote(run))
    os.execute("mkfifo " .. shell_quote(run .. "/ev.fifo") .. " " .. shell_quote(run .. "/cmd.fifo") .. " 2>/dev/null")
    _bs_gen = 1
    write_file(run .. "/gen", "1 " .. (CLEAR_BS and "1" or "0"))
    os.execute("nohup " .. shell_quote(SELF) .. " --bsmon " .. shell_quote(run) .. " "
        .. (CLEAR_BS and "1" or "0")
        .. " > " .. shell_quote(run .. "/bsmon.log") .. " 2>&1 & echo $! > " .. shell_quote(run .. "/mon.pid"))
    _bs = { run = run }
    return true
end

local function bs_bump()
    if _bs then
        _bs_gen = _bs_gen + 1
        write_file(_bs.run .. "/gen", _bs_gen .. " " .. (CLEAR_BS and "1" or "0"))
    end
end

local function bs_stop()
    if _bs then
        local run = _bs.run
        for _, name in ipairs({ "helper.pid", "mon.pid" }) do
            local pid = read_file(run .. "/" .. name)
            if pid and pid:match("^%d+$") then
                os.execute("kill " .. pid .. " 2>/dev/null")
            end
        end
        os.execute("pkill -f " .. shell_quote(run) .. " 2>/dev/null")
        os.execute("rm -rf " .. shell_quote(run))
        _bs = nil
    end
end

local function bsmon_mode()
    local run = arg[2]
    if not run then os.exit(2) end
    local clear_bs = (arg[3] == "1")
    local evf = run .. "/ev.fifo"
    local cmdf = run .. "/cmd.fifo"
    os.execute("mkfifo " .. shell_quote(evf) .. " " .. shell_quote(cmdf) .. " 2>/dev/null")
    local bin = bs_bin or bs_compile()
    if not bin then os.exit(3) end
    bs_bin = bin
    os.execute(shell_quote(bin) .. " " .. shell_quote(evf) .. " " .. shell_quote(cmdf)
        .. " >> " .. shell_quote(run .. "/helper.log") .. " 2>&1 & echo $! > " .. shell_quote(run .. "/helper.pid"))
    local ev = io.open(evf, "r")
    if not ev then os.exit(4) end
    local cmd = io.open(cmdf, "w")
    if not cmd then ev:close(); os.exit(5) end
    local use_wtype = false
    local injected = false
    local function inject_back()
        if injected then return end
        injected = true
        if cmd then cmd:write("1"); cmd:flush() end
        if use_wtype then
            os.execute("wtype -M ctrl -M shift -k Delete -m ctrl -m shift 2>/dev/null")
        end
    end
    local KEY_LEFTCTRL, KEY_RIGHTCTRL = 29, 97
    local KEY_LEFTSHIFT, KEY_RIGHTSHIFT = 42, 54
    local KEY_LEFTALT, KEY_RIGHTALT = 56, 100
    local printable = {}
    for i = 2, 13 do printable[i] = true end
    for i = 16, 27 do printable[i] = true end
    for i = 30, 41 do printable[i] = true end
    printable[43] = true
    printable[86] = true
    for i = 44, 53 do printable[i] = true end
    printable[55] = true
    printable[57] = true
    for i = 71, 83 do printable[i] = true end
    printable[98] = true
    printable[117] = true
    printable[121] = true
    local shadow = ""
    local is_word = {}
    for i = 2, 11 do is_word[i] = true end
    for i = 16, 25 do is_word[i] = true end
    for i = 30, 38 do is_word[i] = true end
    is_word[40] = true
    for i = 44, 50 do is_word[i] = true end
    for i = 71, 73 do is_word[i] = true end
    for i = 75, 77 do is_word[i] = true end
    for i = 79, 82 do is_word[i] = true end
    local function shadow_del_one()
        shadow = shadow:sub(1, #shadow - 1)
    end
    local function shadow_word_back()
        local n = #shadow
        while n > 0 and shadow:sub(n, n) ~= "w" do n = n - 1 end
        while n > 0 and shadow:sub(n, n) == "w" do n = n - 1 end
        shadow = shadow:sub(1, n)
    end
    local lctrl, rctrl, lshift, rshift, lalt, ralt = 0, 0, 0, 0, 0, 0
    local gen_path = run .. "/gen"
    local app_pid = tostring(run:match("run_(%d+)_") or "")
    local cur_gen = nil
    local function sync_gen()
        local raw = read_file(gen_path)
        if not raw then os.exit(0) end
        if app_pid ~= "" and not proc_alive(app_pid) then os.exit(0) end
        local g, cb = raw:match("^(%d+)%s+(%d)")
        if g and g ~= cur_gen then
            cur_gen = g
            clear_bs = (cb == "1")
            shadow = ""
            injected = false
        end
    end
    sync_gen()

    for line in ev:lines() do
        if line == "NODEV" then
            break
        elseif line == "READY" then
            -- helper ready
        elseif line == "NOUINPUT" then
            use_wtype = true
        elseif line:sub(1, 2) == "K " then
            sync_gen()
            local code_s, val_s = line:match("^K (%d+) (%d+)$")
            if code_s then
                local code, val = tonumber(code_s), tonumber(val_s)
                local is_mod = code == KEY_LEFTCTRL or code == KEY_RIGHTCTRL
                    or code == KEY_LEFTSHIFT or code == KEY_RIGHTSHIFT
                    or code == KEY_LEFTALT or code == KEY_RIGHTALT
                if is_mod then
                    if val == 0 then
                        if code == KEY_LEFTCTRL then lctrl = 0
                        elseif code == KEY_RIGHTCTRL then rctrl = 0
                        elseif code == KEY_LEFTSHIFT then lshift = 0
                        elseif code == KEY_RIGHTSHIFT then rshift = 0
                        elseif code == KEY_LEFTALT then lalt = 0
                        elseif code == KEY_RIGHTALT then ralt = 0 end
                    elseif val == 1 or val == 2 then
                        if code == KEY_LEFTCTRL then lctrl = 1
                        elseif code == KEY_RIGHTCTRL then rctrl = 1
                        elseif code == KEY_LEFTSHIFT then lshift = 1
                        elseif code == KEY_RIGHTSHIFT then rshift = 1
                        elseif code == KEY_LEFTALT then lalt = 1
                        elseif code == KEY_RIGHTALT then ralt = 1 end
                    end
                elseif val == 1 or val == 2 then
                    local ctrl = (lctrl + rctrl) > 0
                    local alt = (lalt + ralt) > 0
                    if ctrl and alt then
                        if code == 35 then
                            shadow_word_back()
                        end
                    elseif ctrl and not alt then
                        if code == 17 then
                            shadow = ""
                        elseif code == 22 then
                            if not clear_bs then shadow = "" end
                        elseif code == 14 then
                            shadow_word_back()
                        elseif code == 35 or code == 32 then
                            if not clear_bs then shadow_del_one() end
                        elseif code == 47 then
                            local cb = shell("wl-paste 2>/dev/null")
                            if cb and cb ~= "" then
                                shadow = shadow .. string.rep("?", utf8.len(cb) or #cb)
                            end
                        end
                    elseif not alt then
                        if code == 14 then
                            local empty = (#shadow == 0)
                            if clear_bs then shadow = ""
                            else shadow_del_one() end
                            if empty then inject_back() end
                        elseif printable[code] then
                            shadow = shadow .. (is_word[code] and "w" or "s")
                        end
                    end
                end
            end
        end
    end
    ev:close()
    os.exit(0)
end

if arg[1] == "--bsmon" then
    bsmon_mode()
    return
end

-- ── Icons ─────────────────────────────────────────────────────────────

local icons
local ok = pcall(function()
    icons = assert(loadfile(ICONS))()
end)
if not ok then icons = { files = {}, dirs = {}, exts = {} } end

local COLOR = {
    dir     = "#9bbfbf",
    link    = "#c8a4e0",
    orphan  = "#e78284",
    exec    = "#fab387",
    image   = "#b6e0a4",
    audio   = "#e0d8a4",
    video   = "#e0d8a4",
    archive = "#fab387",
    doc     = "#9bbfbf",
    default = "#dfdfdd",
}

local GLYPH_COLOR = {
    ["󰎅 "] = COLOR.audio,   -- audio
    [" "] = COLOR.video,   -- video
    [" "] = COLOR.image,   -- image
    [" "] = COLOR.archive, [" "] = COLOR.archive, ["󰪶 "] = COLOR.archive,
    [" "] = COLOR.archive, ["󱧘 "] = COLOR.archive,
    [" "] = COLOR.doc, [" "] = COLOR.doc, [" "] = COLOR.doc, ["󰐩 "] = COLOR.doc,
    [" "] = COLOR.exec,
}

local function icon_for(kind, name, ext, is_exec)
    if kind == "dir" then
        return icons.dirs[name:lower()] or " ", COLOR.dir
    elseif kind == "link" then
        return " ", COLOR.link
    elseif kind == "sock" then
        return " ", COLOR.default
    elseif kind == "fifo" then
        return " ", COLOR.default
    elseif kind == "char" then
        return " ", COLOR.default
    elseif kind == "block" then
        return " ", COLOR.default
    end
    if is_exec then
        return " ", COLOR.exec
    end
    local glyph = icons.files[name:lower()] or (ext ~= "" and icons.exts[ext]) or " "
    return glyph, GLYPH_COLOR[glyph] or COLOR.default
end

local function row(glyph, color, name)
    return '<span foreground="' .. color .. '">' .. glyph .. "</span> " .. pango_escape(name)
end

-- ── Listing ───────────────────────────────────────────────────────────

local function list_dir(dir)
    local cmd = "find " .. shell_quote(dir) .. " -mindepth 1 -maxdepth 1 -printf '%y\\t%M\\t%f\\n' 2>/dev/null"
    local p = io.popen(cmd)
    if not p then return {}, {} end
    local out = p:read("*a"); p:close()

    local dirs, files = {}, {}
    for line in (out or ""):gmatch("(.-)\n") do
        local kind, perm, name = line:match("^(.)\t([^\t]*)\t(.*)$")
        if kind and name then
            local is_exec = perm:find("x") ~= nil
            local ext = name:match("%.([^%.]+)$") or ""
            if kind == "d" then
                dirs[#dirs + 1] = { kind = "dir", name = name, ext = ext }
            elseif kind == "l" then
                files[#files + 1] = { kind = "link", name = name, ext = ext }
            elseif kind == "s" then
                files[#files + 1] = { kind = "sock", name = name, ext = ext }
            elseif kind == "p" then
                files[#files + 1] = { kind = "fifo", name = name, ext = ext }
            elseif kind == "c" then
                files[#files + 1] = { kind = "char", name = name, ext = ext }
            elseif kind == "b" then
                files[#files + 1] = { kind = "block", name = name, ext = ext }
            else
                files[#files + 1] = { kind = "file", name = name, ext = ext, exec = is_exec }
            end
        end
    end

    local function cmp(a, b)
        local an, bn = a.name:lower(), b.name:lower()
        if an == bn then return a.name < b.name end
        return an < bn
    end
    table.sort(dirs, cmp)
    table.sort(files, cmp)
    return dirs, files
end

local function browse_entries(dir)
    local dirs, files = list_dir(dir)
    local entries = {}
    for _, d in ipairs(dirs) do
        local glyph, color = icon_for(d.kind, d.name, d.ext)
        entries[#entries + 1] = row(glyph, color, d.name)
    end
    for _, f in ipairs(files) do
        local glyph, color = icon_for(f.kind, f.name, f.ext, f.exec)
        entries[#entries + 1] = row(glyph, color, f.name)
    end
    return entries
end

-- ── Rofi ──────────────────────────────────────────────────────────────

local function rofi_dmenu(entries, mesg, glyph, selected_row)
    local entry_tf = os.tmpname()
    local f = io.open(entry_tf, "w")
    if not f then os.remove(entry_tf); return nil, -1 end
    for _, e in ipairs(entries) do f:write(e, "\n") end
    f:close()

    local out_tf = os.tmpname()
    local args = "-markup-rows -no-auto-select -i"
        .. " -kb-custom-1 'Control+Shift+Delete'"
        .. " -kb-custom-2 'Tab'"
        .. " -kb-accept-alt ''" -- frees Shift+Return, which it holds by default
        .. " -kb-custom-3 'Shift+Return'"
        .. " -kb-element-next ''"
    if selected_row and selected_row >= 0 then
        args = args .. " -selected-row " .. tostring(selected_row)
    end
    if glyph then
        args = args .. " -theme-str " .. shell_quote('textbox-prompt-colon { str: "' .. glyph .. '"; }')
    end
    local cmd = string.format(
        "rofi -dmenu -config %s -theme %s -p %s -mesg %s %s < %s > %s 2>/dev/null; printf '\\n__EXIT__%%d__' $? >> %s",
        shell_quote(CONFIG), shell_quote(THEME), shell_quote(""),
        shell_quote(mesg), args, shell_quote(entry_tf), shell_quote(out_tf), shell_quote(out_tf))
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

-- ── Main ──────────────────────────────────────────────────────────────

local cwd = read_file(STATE) or HOME
if not is_dir(cwd) then cwd = HOME end

local browse_row = 0

-- Absolute path behind a rofi row, or nil when nothing was selected.
local function entry_path(raw)
    local name = strip_markup(raw or "")
    if name == "" then return nil end
    if name:sub(1, 1) == "/" then return name end
    return cwd .. "/" .. name
end

-- Index of a rofi row in the current listing, for restoring the selection.
local function entry_row(entries, raw)
    local name = strip_markup(raw or "")
    for i, e in ipairs(entries) do
        if strip_markup(e) == name then return i - 1 end
    end
    return browse_row
end

local function run_native_search()
    bs_stop()
    os.remove(OPENED_SENTINEL)
    os.remove(ESC_SENTINEL)
    os.execute(string.format(
        -- recursivebrowser fills the message textbox with its own "Current
        -- directory" line, so -mesg is ignored here; the binds ride in a second
        -- textbox that fatsearch.rasi styles as part of the same block.
        "rofi -i -show recursivebrowser -disable-history -config %s -theme %s -theme-str %s"
            .. " -kb-element-next '' -kb-mode-complete 'Tab'"
            .. " -on-menu-canceled %s 2>/dev/null",
        shell_quote(SEARCH_CONFIG), shell_quote(SEARCH_THEME),
        shell_quote('textbox-binds { str: "' .. SEARCH_BINDS .. '"; }'),
        shell_quote("touch " .. shell_quote(ESC_SENTINEL))))
    local opened = read_file(OPENED_SENTINEL)
    os.remove(OPENED_SENTINEL)
    local escaped = read_file(ESC_SENTINEL)
    os.remove(ESC_SENTINEL)
    bs_start()
    -- opened  = file accepted -> open it and exit
    -- escaped = Esc pressed   -> close the window
    -- other   = Tab pressed   -> back to filemanager
    if opened then return "opened" end
    if escaped then return "escaped" end
    return "tab"
end

bs_start()

while true do
    bs_bump()

    local entries = browse_entries(cwd)
    local mesg = pango_escape(cwd) .. "\n" .. BROWSE_BINDS

    local raw, code = rofi_dmenu(entries, mesg, nil, browse_row)
    if code == 10 then
        -- Backspace on empty filter: injected Control+Shift+Delete
        cwd = parent_dir(cwd)
        write_file(STATE, cwd)
        browse_row = 0
    elseif code == 11 then
        -- Tab: launch rofi's native recursivebrowser search at ~
        browse_row = entry_row(entries, raw)
        local search = run_native_search()
        if search == "opened" or search == "escaped" then
            break
        end
        -- "tab": return to filemanager (stay in browse loop)
    elseif code == 12 then
        -- Shift+Return: hand the selected directory to DIR_OPENER
        local path = entry_path(raw)
        if path and is_dir(path) then
            open_dir(resolve(path))
            break
        end
        browse_row = entry_row(entries, raw)
    elseif not raw then
        break
    else
        local path = entry_path(raw)
        if path and is_dir(path) then
            cwd = resolve(path)
            write_file(STATE, cwd)
            browse_row = 0
        elseif is_file(path) then
            open_path(path)
            break
        end
    end
end

bs_stop()
os.exit(0)
