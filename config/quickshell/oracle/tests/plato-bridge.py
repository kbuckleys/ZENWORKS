#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# plato's bridge, end to end, with no window: a headless nvim started the way
# NvimClient starts it, driven over its socket the way NvimClient drives it,
# and the JSON that comes back checked against what the screen should say.
#
#     python3 oracle/tests/plato-bridge.py
#
# Not part of test.js — that runner loads pure .js modules into a sandbox,
# and this needs a real nvim. NVIM_APPNAME=plato-test keeps its undo files and
# rescue folder away from the real plato's, PLATO_QUIET keeps the rescue
# notification off the desktop, and PLATO_NO_PLUGINS keeps it offline: the
# engine is tested bare, with nvim's bundled parsers only.

import json, os, select, shutil, signal, socket, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
INIT = os.path.normpath(os.path.join(HERE, "../../plato/nvim/init.lua"))
STATE = os.path.expanduser("~/.local/state/plato-test")

passed = failed = 0
def check(name, ok, detail=""):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1
        print(f"  FAIL {name} {detail}")

class Bridge:
    def __init__(self, tmp, name="t"):
        self.sock_path = os.path.join(tmp, name + ".sock")
        env = dict(os.environ, NVIM_APPNAME="plato-test", PLATO_SOCK=self.sock_path,
                   PLATO_QUIET="1", PLATO_NO_PLUGINS="1")
        self.proc = subprocess.Popen(["nvim", "--headless", "-u", INIT], env=env,
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.s = socket.socket(socket.AF_UNIX)
        for _ in range(200):
            try: self.s.connect(self.sock_path); break
            except OSError: time.sleep(0.02)
        else:
            # not left behind: an nvim that never listened has no bridge, so
            # no grace to end it, and nothing below knows it exists
            self.proc.kill()
            raise SystemExit("bridge never listened: " + self.proc.stderr.read().decode(errors="replace")[-400:])
        self.f = self.s.makefile("rb")
        self.rows, self.last = [], None
        self.events = []
        self.frames = []
        self.styles = {}

    def send(self, method, **params):
        self.s.sendall((json.dumps({"method": method, "params": params}) + "\n").encode())

    # read until nothing has arrived for `quiet` seconds, folding view frames
    # into a screen the way EditorState does
    def settle(self, quiet=0.15):
        while select.select([self.s], [], [], quiet)[0]:
            line = self.f.readline()
            if not line: return
            ev = json.loads(line)
            if ev.get("event") in ("view", "theme"):
                for st in ev.get("styles") or []: self.styles[st["id"]] = st
            if ev.get("event") == "view":
                # the current window's rows and cursor; splits are tested by
                # looking at ev["wins"] directly
                w = next(x for x in ev["wins"] if x["current"])
                self.wins = ev["wins"]
                h = w["height"]
                if w["full"] or len(self.rows) != h:
                    self.rows = (self.rows + [None] * h)[:h]
                for r in w["rows"]: self.rows[r["i"]] = r
                ev["cursor"] = w["cursor"]
                self.last = ev
                self.frames.append(ev)
            elif "event" in ev:
                self.events.append(ev)

    def keys(self, k):
        self.send("input", keys=k); self.settle()

    def text(self):
        return [r["t"] for r in self.rows if r and r["n"] > 0]

    def cursor(self):
        return (self.last["cursor"]["row"], self.last["cursor"]["col"])

    # the style of the span covering cell `col` of screen row `i`
    def style_at(self, i, col):
        for sp in self.rows[i]["s"]:
            if sp[0] <= col < sp[0] + sp[1]: return self.styles.get(sp[2], {})
        return {}

tmp = tempfile.mkdtemp(prefix="plato-test-")
shutil.rmtree(STATE, ignore_errors=True)
try:
    doc = os.path.join(tmp, "doc.txt")
    with open(doc, "w") as fh: fh.write("one\ttab\ntwo\nthree\n")

    b = Bridge(tmp)
    b.send("resize", rows=10, cols=40)
    b.send("open", path=doc); b.settle(0.3)
    check("hello comes first", True)
    check("the file is on screen", b.text() == ["one tab", "two", "three"], b.text())
    check("rows past the end are empty", b.rows[3]["n"] == 0)
    check("tab expands to the next stop of 4", b.rows[0]["t"] == "one tab")

    b.keys("ihello <Esc>")
    check("insert then Esc: text", b.text()[0] == "hello one   tab", b.text())
    check("insert then Esc: cursor back one", b.cursor() == (0, 5), b.cursor())
    check("modified", b.last["modified"] is True)

    # nostartofline (nvim's default): dd keeps the column the cursor wanted —
    # 5, from the first line — clamped to the end of "three"
    b.keys("jdd")
    check("dd removes the line", b.text() == ["hello one   tab", "three"], b.text())
    check("dd: cursor keeps its column", b.cursor() == (1, 4), b.cursor())

    b.keys("u")
    check("u restores it", b.text() == ["hello one   tab", "two", "three"], b.text())
    b.keys("<C-r>")
    check("C-r redoes", b.text() == ["hello one   tab", "three"], b.text())

    b.keys("ggciwHELLO<Esc>")
    check("ciw", b.text()[0] == "HELLO one   tab", b.text())

    b.keys("0f<Tab>")
    check("normal mode sits at a tab's end", b.cursor() == (0, 11), b.cursor())

    b.keys(":w<CR>")
    with open(doc) as fh: saved = fh.read()
    check(":w writes the file", saved == "HELLO one\ttab\nthree\n", repr(saved))
    check("written means not modified", b.last["modified"] is False)
    msgs = [e for e in b.events if e.get("event") == "msg"]
    check("messages reach plato, and never carry `id` (that marks a reply, and the client drops it)",
          msgs and all("id" not in e for e in msgs), msgs[-2:])
    check("the command line was shown and hidden",
          any(e.get("event") == "cmdline" and e["shown"] is False for e in b.events))

    # scrolling: nvim owns the viewport, the frame reports where it went
    with open(doc, "w") as fh: fh.write("".join(f"line {i}\n" for i in range(1, 41)))
    b.keys(":e!<CR>")
    b.keys("G")
    check("G scrolls the last line into view", b.rows[-1]["n"] == 40, b.rows[-1])
    check("and the cursor is on it", b.cursor()[0] == 9, b.cursor())
    # ONE KEY PER REQUEST, as a keyboard sends them: the second key of a
    # command arrives while nvim waits for it, and must still get in. (They
    # used to sit behind the main loop, which a waiting nvim does not run:
    # gg froze the window, 10j did nothing.)
    for k in "gg": b.send("input", keys=k)
    b.settle()
    check("g then g, apart: the top", b.last["line"] == 1, b.last["line"])
    for k in "10j": b.send("input", keys=k)
    b.settle()
    check("1, 0, j apart: ten lines down", b.last["line"] == 11, b.last["line"])
    # the command line is in the frame: a headless nvim never sends
    # cmdline_show, and ":" used to open nothing
    for k in ":e x": b.send("input", keys=k)
    b.settle()
    cl = b.last.get("cmdline") or {}
    check("the command line rides on the frame",
          cl.get("firstc") == ":" and cl.get("text") == "e x" and cl.get("pos") == 3, cl)
    b.keys("<Esc>")
    check("and leaves it when closed", not b.last.get("cmdline"), b.last.get("cmdline"))
    b.send("cmd", cmd="normal! G"); b.send("input", keys="k"); b.settle()
    check("a key after a slow request waits for it", b.last["line"] == 39, b.last["line"])
    b.send("input", keys="d"); b.send("scroll", lines=1); b.send("input", keys="d")
    b.settle()
    check("a key behind a slow request nvim cannot run yet still gets in",
          b.last["lines"] == 39, b.last["lines"])
    b.keys("u")
    # a request that asks for input from inside itself gets its answer
    b.send("cmd", cmd="lua vim.ui.input({ prompt = 'name: ' }, function(t) vim.g.answer = t end)")
    for k in "abc": b.send("input", keys=k)
    b.send("input", keys="<CR>"); b.settle()
    b.send("cmd", cmd="lua vim.notify('answer=' .. tostring(vim.g.answer))"); b.settle()
    check("a prompt inside a request is answered by the keys after it",
          any(e.get("text") == "answer=abc" for e in b.events), [e.get("text") for e in b.events][-3:])
    b.keys("gg")
    b.send("scroll", lines=5); b.settle()
    check("scroll moves the top line", b.rows[0]["n"] == 6, b.rows[0])

    # a closed fold is one row
    b.keys("ggzfjj")
    check("a fold is one row", b.rows[0]["f"] and b.rows[1]["n"] == 3, b.rows[:2])

    b.send("resize", rows=4, cols=20); b.settle()
    check("resize shrinks the screen", len(b.rows) == 4)

    # ── phase 2: what the screen looks like ─────────────────────────────
    MAGENTA, CYAN, RED, PINK, GREY = "#c8a4e0", "#9bbfbf", "#e78284", "#eebebe", "#6a707f"
    lua = os.path.join(tmp, "t.lua")
    with open(lua, "w") as fh: fh.write('local x = 42 -- note\nreturn "s"\n')
    b.send("resize", rows=8, cols=40)
    b.send("open", path=lua); b.settle(0.3)
    check("treesitter: a keyword is magenta", b.style_at(0, 0).get("fg") == MAGENTA, b.rows[0])
    check("treesitter: a comment is grey", b.style_at(0, 14).get("fg") == GREY, b.rows[0])
    check("treesitter: a string is cyan", b.style_at(1, 8).get("fg") == CYAN, b.rows[1])
    check("plain Normal text carries no span", b.style_at(0, 5) == {}, b.rows[0])

    js = os.path.join(tmp, "t.js")
    with open(js, "w") as fh:
        fh.write("function two(a) {\n  return a + two;\n}\n" + "x" * 70 + "\n")
    b.send("open", path=js); b.settle(0.3)
    check("regex syntax: a keyword is magenta", b.style_at(0, 0).get("fg") == MAGENTA, b.rows[0])

    # from the top, /two lands on the first one — the function's name
    b.keys("/two<CR>")
    check("search: the match at the cursor is CurSearch",
          b.style_at(0, 9).get("bg") == RED, (b.cursor(), b.rows[0]))
    check("search: the others are Search", b.style_at(1, 13).get("bg") == PINK, b.rows[1])
    b.keys("<Esc>")
    check("<Esc> clears the search highlight", b.style_at(0, 9).get("bg") is None, b.rows[0])

    b.keys("ggVj")
    sel = b.rows[1]["s"]
    # a wash over the text (hl.lua's `wash`): the syntax colours stay, so a
    # selected line may be several spans — every one of them selected
    check("a line-wise selection covers the whole line",
          sel and all(b.styles[x[2]].get("bg") == MAGENTA for x in sel)
          and sel[0][0] == 0 and all(sel[i][0] + sel[i][1] == sel[i + 1][0] for i in range(len(sel) - 1)), sel)
    check("reaching one cell past the text", sel and sel[-1][0] + sel[-1][1] == len(b.rows[1]["t"]), sel)
    check("and drawn translucent", sel and all(b.styles[x[2]].get("a") for x in sel), sel)
    b.keys("<Esc>")

    check("a long line wraps onto a second row",
          b.rows[3]["n"] == 4 and b.rows[4]["n"] == 4 and b.rows[4]["k"] == 1,
          [(r["n"], r["k"]) for r in b.rows[3:5]])
    check("a wrapped row has no number of its own", b.rows[4]["k"] == 1)

    b.keys(':lua vim.diagnostic.set(vim.api.nvim_create_namespace("t"), 0, '
           '{{lnum=1, col=2, end_col=8, severity=1, message="nope, this is far too long to fit"}})<CR>')
    r1 = b.rows[1]
    check("a diagnostic puts its sign in the gutter", r1.get("g") and r1["g"][0] == "E", r1)
    check("its text follows the line", "▪ nope" in r1["t"], r1["t"])
    check("cut at the edge, not wrapped", len(r1["t"]) <= 40 and b.rows[2]["n"] == 3,
          (r1["t"], b.rows[2]["n"]))
    check("the diagnosed range is underlined", b.style_at(1, 3).get("u") or b.style_at(1, 3).get("c"), b.rows[1])

    wide = os.path.join(tmp, "w.txt")
    with open(wide, "w") as fh: fh.write("日本 abc\n")
    b.send("open", path=wide); b.settle()
    b.keys("/abc<CR>")
    sp = b.rows[0]["s"][0] if b.rows[0]["s"] else []
    check("wide characters: spans carry character offsets too", sp[:2] == [5, 3] and sp[3:] == [3, 3], sp)
    b.keys("<Esc>")

    # ── phase 3: splits are nvim's windows, laid out where nvim put them ─
    b.send("resize", rows=12, cols=60); b.settle()
    b.keys(":vsplit<CR>")
    ws = sorted(b.wins, key=lambda w: w["col"])
    check("a vertical split is two windows side by side",
          len(ws) == 2 and ws[0]["row"] == ws[1]["row"] and ws[1]["col"] > ws[0]["col"], ws)
    check("each has its own gutter", all(w["textoff"] >= 3 for w in ws), [w["textoff"] for w in ws])
    check("the left is current after :vsplit", ws[0]["current"], ws)
    b.keys("<C-w>l")
    ws = sorted(b.wins, key=lambda w: w["col"])
    check("<C-w>l moves into the right one", ws[1]["current"] and not ws[0]["current"], ws)
    b.keys(":only<CR>")
    check(":only leaves one", len(b.wins) == 1, b.wins)

    # an explicit quit with nothing modified: gone at once, nothing rescued
    b.send("quit"); b.proc.wait(timeout=3)
    check("quit exits", b.proc.returncode is not None)
    check("nothing to rescue", not os.path.isdir(os.path.join(STATE, "rescue")))

    # the grace: a client that vanishes with an unsaved buffer
    b2 = Bridge(tmp, "grace")
    b2.send("resize", rows=5, cols=40)
    b2.send("open", path=doc)
    # sent in the same breath as the open, as a window does: the keys must
    # land in the file, not in the empty buffer before it
    b2.send("input", keys="iunsaved <Esc>")
    b2.settle()
    check("keys sent right after open reach the file",
          b2.text()[:1] == ["unsaved line 1"], b2.text()[:1])
    t0 = time.time()
    # makefile() holds its own reference: both must go for nvim to see EOF
    b2.f.close()
    b2.s.close()
    try: b2.proc.wait(timeout=9)
    except subprocess.TimeoutExpired: pass
    gone = b2.proc.poll() is not None
    check("a lost client's nvim quits after the grace", gone)
    check("but not before it", not gone or time.time() - t0 > 4, time.time() - t0)
    rescued = os.listdir(os.path.join(STATE, "rescue")) if os.path.isdir(os.path.join(STATE, "rescue")) else []
    check("its unsaved buffer was rescued", len(rescued) == 1, rescued)
    if rescued:
        with open(os.path.join(STATE, "rescue", rescued[0])) as fh:
            check("with the unsaved text", fh.readline().startswith("unsaved line 1"))
    with open(doc) as fh:
        check("and the file itself untouched", fh.readline() == "line 1\n")
    # A MAIN LOOP STUCK ON A PROMPT, with nobody left to answer it: the polite
    # exit can never run, and before the deadline an engine like this lived
    # for good (three were found alive eleven hours on). The deadline does
    # not need the main loop, so it still goes: grace, plus ten seconds.
    b3 = Bridge(tmp, "stuck")
    b3.send("resize", rows=5, cols=40); b3.settle()
    # a wait on something that never happens: the event loop keeps turning
    # (sockets are still accepted) but nothing scheduled ever runs again —
    # how the orphans were found, idle in epoll with no greeting for anyone
    b3.send("cmd", cmd="lua vim.wait(600000, function() return false end)")
    time.sleep(0.5)
    b3.send("ping"); 
    stuck = not select.select([b3.s], [], [], 1.0)[0] or b3.f.readline() == b""
    check("a prompt with nobody to answer it blocks the main loop", stuck)
    t0 = time.time()
    b3.f.close(); b3.s.close()
    try: b3.proc.wait(timeout=25)
    except subprocess.TimeoutExpired: pass
    check("and the engine still exits, by its deadline", b3.proc.poll() is not None,
          round(time.time() - t0, 1))
    # ── 2026-10-03: the settings sheet, :w with no name, fork, flashes ──
    fresh = os.path.join(tmp, "fresh.txt")
    with open(fresh, "w") as fh: fh.write("alpha beta\ngamma\ndelta\n")
    b4 = Bridge(tmp, "fresh")
    b = b4
    b.send("resize", rows=10, cols=40)
    b.send("open", path=fresh); b.settle(0.3)
    b.events.clear()
    for k in ["y", "y"]: b.keys(k)
    fl = [e for e in b.events if e.get("event") == "flash"]
    check("yy flashes its whole line", fl and fl[-1]["kind"] == "yank" and fl[-1]["linewise"]
          and fl[-1]["cells"][0]["row"] == 0, fl)
    b.events.clear()
    for k in ["w", "d", "w"]: b.keys(k)
    fl = [e for e in b.events if e.get("event") == "flash"]
    tx = b.wins[0]["textoff"]
    check("dw flashes the word it took, where it was",
          fl and fl[-1]["kind"] == "delete" and fl[-1]["cells"][0]["col"] == tx + 6
          and fl[-1]["cells"][0]["len"] == 4, fl)
    b.keys("u")
    b.send("options", tabWidth=2, expandTab=False, smartCase=False, editFlash=False); b.settle()
    b.events.clear()
    b.keys(":lua print(vim.bo.tabstop, vim.o.expandtab, vim.o.ignorecase)<CR>")
    said = [e["text"] for e in b.events if e.get("event") == "msg"]
    check("options reach nvim", said[-1:] == ["2 false false"], said)
    b.events.clear()
    for k in ["y", "y"]: b.keys(k)
    check("flashes switched off send nothing",
          not [e for e in b.events if e.get("event") == "flash"])
    b.send("options", tabWidth=4, expandTab=True, smartCase=True, editFlash=True); b.settle()

    for k in ["V", "j"]: b.keys(k)
    b.send("fork"); b.settle(0.3)
    check("fork: the selection, in a new buffer with no file",
          b.text() == ["alpha beta", "gamma"] and b.last["file"] == "" and b.last["modified"],
          (b.text(), b.last["file"]))
    check("fork: in normal mode, in the same language", b.last["mode"] == "n")
    got = []
    b.send("root"); b.settle()
    b.s.sendall((json.dumps({"id": 900, "method": "root", "params": {}}) + "\n").encode())
    while select.select([b.s], [], [], 0.5)[0] or b.f.peek():
        ev = json.loads(b.f.readline())
        if ev.get("id") == 900: got.append(ev["result"]); break
    check("a buffer with no file is rooted at home", got == [os.path.expanduser("~")], got)
    b.events.clear()
    for k in [":", "w", "q", "<CR>"]: b.keys(k)
    sa = [e for e in b.events if e.get("event") == "saveAs"]
    check(":wq with no file asks plato for its save dialog", sa == [{"event": "saveAs", "quit": True}], sa)
    check("and nvim is still here, out of the command line", b.last["mode"] == "n")
    b.keys(":bwipeout!<CR>")
    b.keys(":enew<CR>")
    b.events.clear()
    for k in [":", "e", "c", "h"]: b.keys(k)
    pum = [e for e in b.events if e.get("event") == "pum" and e.get("shown")]
    check("the : line offers completions as you type",
          pum and pum[-1].get("cmdline") and any(i["word"] == "echo" for i in pum[-1]["items"]), pum[-1:])
    b.keys("<Esc>")

    # ── 2026-10-03: live :s, sticky scroll, the yank history, peek, zen ──
    def ask(bb, method, **params):
        bb.s.sendall((json.dumps({"id": 901, "method": method, "params": params}) + "\n").encode())
        while True:
            ev = json.loads(bb.f.readline())
            if ev.get("id") == 901: return ev.get("result")
    seen = []
    rl = b.f.readline
    def watching():
        line = rl()
        try:
            ev = json.loads(line)
            if ev.get("event") == "view": seen.append(ev)
        except Exception: pass
        return line
    b.f.readline = watching
    nest = os.path.join(tmp, "nest.lua")
    with open(nest, "w") as fh:
        fh.write("local M = {}\nfunction M.a(x)\n  if x then\n"
                 + "".join(f"    print({i})\n" for i in range(40)) + "  end\nend\nreturn M\n")
    b.send("open", path=nest); b.settle(0.3)
    b.keys("30G")
    ctx = [e["context"] for e in seen if e.get("context") is not None]
    check("sticky scroll: the function and the if the view is inside",
          ctx and [c["n"] for c in ctx[-1]] == [2, 3], ctx[-1:])
    check("and coloured as the view colours them",
          ctx and any(ch[1] for ch in ctx[-1][0]["chunks"]), ctx[-1:])
    b.keys("gg")
    for k in ":%s/print/PUT/": b.keys(k)
    check(":s shows what it would do while it is typed",
          "    PUT(0)" in b.text(), b.text()[:6])
    b.keys("<Esc>")
    check("and nothing was done", "    print(0)" in b.text(), b.text()[:6])
    b.keys("4G")
    for k in ["y", "y", "j", "y", "y"]: b.keys(k)
    ys = ask(b, "yanks")
    check("the yank history, newest first", [y["text"] for y in ys[:2]] == ["    print(1)", "    print(0)"], ys[:2])
    ask(b, "putYank", index=2); b.settle()
    tx = b.text()
    check("putting one back puts it after the cursor",
          any(tx[i] == "    print(1)" and tx[i + 1] == "    print(0)" for i in range(len(tx) - 1)), tx)
    b.keys("u")
    b.send("cmd", cmd=f"lua require('plato.peek').open({{filename='{fresh}', lnum=2, col=1}})"); b.settle(0.3)
    fl = [e["floats"] for e in seen if e.get("floats")]
    check("peek opens a titled card with the cursor in it",
          fl and fl[-1][0].get("title", "").endswith("fresh.txt:2") and fl[-1][0].get("cursor") is not None, fl[-1:])
    b.keys("q")
    check("q closes it", b.last.get("inFloat") is False and not [e for e in seen[-1:] if e.get("floats")], seen[-1].get("floats"))
    b.send("options", zen=True); b.settle()
    b.keys("10G")
    check("zen: the cursor's paragraph", seen[-1].get("para") == [1, 46], seen[-1].get("para"))
    b.send("options", zen=False); b.settle()
    b.f.readline = rl

    # undo sweeps back over what it changed, redo forward; a new edit does not
    b.send("open", path=fresh); b.settle(0.3)
    b.keys("gg")
    for k in ["j", "d", "d"]: b.keys(k)
    b.events.clear(); b.keys("u")
    fl = [e for e in b.events if e.get("event") == "flash"]
    check("undo flashes the lines it brought back", fl and fl[-1]["kind"] == "undo"
          and fl[-1]["cells"][0]["row"] == 1, fl)
    b.events.clear(); b.keys("<C-r>")
    fl = [e for e in b.events if e.get("event") == "flash"]
    check("redo flashes too", fl and fl[-1]["kind"] == "redo", fl)
    b.events.clear()
    for k in ["A", "x", "<Esc>"]: b.keys(k)
    check("a new edit does not", not [e for e in b.events if e.get("event") == "flash"])
    b.events.clear(); b.keys("u")
    fl = [e for e in b.events if e.get("event") == "flash"]
    check("and undoing what was just typed does", fl and fl[-1]["kind"] == "undo", fl)
    b.keys("u")

    # ── the status line's facts (status.lua) ─────────────────────────────
    stat = {}
    rl2 = b.f.readline
    def statusWatch():
        line = rl2()
        try:
            ev = json.loads(line)
            if ev.get("event") == "view" and ev.get("status"): stat.update(ev["status"])
        except Exception: pass
        return line
    b.f.readline = statusWatch
    b.send("open", path=fresh); b.settle(0.3)
    b.keys("gg"); b.keys("2"); b.keys("d")
    check("an operator waiting: its keys and op", stat.get("pending") == "2d" and stat.get("op") is True, stat)
    b.keys("<Esc>")
    check("and gone once it is answered", stat.get("pending") == "" and stat.get("op") is False, stat)
    b.keys("qa")
    check("recording a macro says which register", stat.get("rec") == "a", stat.get("rec"))
    b.keys("q")
    check("and stops saying it", stat.get("rec") == "", stat.get("rec"))
    b.keys("Vj")
    check("a selection is counted", stat.get("sel", {}).get("lines") == 2, stat.get("sel"))
    b.keys("<Esc>")
    check("the indent and line endings", stat.get("indent", {}).get("width") and stat.get("eol") == "unix", stat)
    check("no git outside a repository", stat.get("branch") == "", stat.get("branch"))
    b.f.readline = rl2

    # :cdo s/// (replace in the project) is previewed on the quickfix lines
    b.keys("gg")
    b.send("cmd", cmd="lua vim.fn.setqflist({}, ' ', { items = { { bufnr = vim.api.nvim_get_current_buf(), lnum = 2, col = 1 } } })"); b.settle()
    for k in [":", "cdo s/a/A/g | update"]: b.keys(k)
    tx = b.text()
    check(":cdo s/// previews only the quickfix lines", tx[1] == "gAmmA" and tx[0] == "alpha beta", tx[:3])
    b.keys("<Esc>")

    # the undo history: newest first, where you are marked, a diff to go back
    b.keys("ggAzz<Esc>")
    us = ask(b, "undoList")
    check("the undo history marks where you are", us and us[0]["current"] and us[0]["detail"] == "you are here", us[:2])
    df = ask(b, "undoPreview", seq=us[1]["seq"])
    check("and previews going back as a diff", "zz" in df and df.lstrip().startswith("@@"), df[:120])
    ask(b, "undoTo", seq=us[1]["seq"]); b.settle()
    check("going back undoes it", "zz" not in b.text()[0], b.text()[0])

    # pinned files: on Alt, and on the tab
    ask(b, "cmd", cmd="lua require('plato.pins').toggle()"); b.settle(0.3)
    ps = ask(b, "pins")
    check("a file pinned is number 1", ps and ps[0]["n"] == 1 and ps[0]["path"] == fresh, ps)
    ask(b, "unpin", path=fresh)
    check("and unpinned again", ask(b, "pins") in ([], {}), ask(b, "pins"))

    b4.send("quit"); b4.proc.wait(timeout=3)

    # ── 2026-10-04 audit: regressions for what it found ────────────────
    b5 = Bridge(tmp, "audit")
    b5.send("resize", rows=12, cols=60)
    proj = os.path.join(tmp, "proj")
    os.makedirs(os.path.join(proj, "sub"))
    with open(os.path.join(proj, ".git"), "w") as fh: fh.write("")
    sfile = os.path.join(proj, "sub", "s.txt")
    with open(sfile, "w") as fh: fh.write("foo a foo\nbar\nfoo\n")
    b5.send("open", path=sfile); b5.settle(0.3)

    # the search count, from the cached match list: total, and where you are
    b5.keys("/foo<CR>")
    b5.keys("gg0")
    check("search count: first match", (b5.last["search"] or {}).get("current") == 1
          and b5.last["search"].get("total") == 3, b5.last["search"])
    b5.keys("4l")
    check("search count: between matches counts those before",
          b5.last["search"].get("current") == 1, b5.last["search"])
    b5.keys("G")
    check("search count: the last", b5.last["search"].get("current") == 3, b5.last["search"])
    b5.keys("<Esc>")

    # project replace: two matches on one line are one quickfix entry, so
    # nothing reports E486 and every one is replaced
    b5.events.clear()
    rp = ask(b5, "projectReplace", root=proj, query="foo"); b5.settle()
    check("project replace uses ge", rp and rp["cmd"].endswith("//ge | update"), rp)
    b5.send("input", keys=":" + rp["cmd"].replace("<", "<lt>") + "<Left>" * rp["back"]); b5.settle()
    b5.keys("BAR<CR>"); b5.settle(0.3)
    with open(sfile) as fh: got = fh.read()
    check("project replace: every match replaced", got == "BAR a BAR\nbar\nBAR\n", repr(got))
    errs = [e for e in b5.events if e.get("event") == "msg" and "E486" in (e.get("text") or "")]
    check("project replace: no E486 for a line with two matches", not errs, errs)

    # :s previewed in the current window only, not in a split beside it
    other = os.path.join(proj, "other.txt")
    with open(other, "w") as fh: fh.write("bar\nbar\n")
    b5.send("cmd", cmd="vsplit " + other); b5.settle(0.3)
    b5.send("cmd", cmd="wincmd l"); b5.settle()
    b5.frames.clear()
    for k in [":", "%s/bar/ZZZ/"]: b5.keys(k)
    cur = [w for w in b5.wins if w["current"]][0]["id"]
    leaked = [r["t"] for f in b5.frames for w in f["wins"] if w["id"] != cur
              for r in w["rows"] if "ZZZ" in r["t"]]
    shown = [r["t"] for f in b5.frames for w in f["wins"] if w["id"] == cur
             for r in w["rows"] if "ZZZ" in r["t"]]
    check(":s preview in its own window", bool(shown), shown)
    check(":s preview not in the split beside it", not leaked, leaked)
    b5.keys("<Esc>")
    b5.send("cmd", cmd="only"); b5.settle()

    # the cursor's character on a row with wide characters before it
    wide = os.path.join(proj, "wide.txt")
    with open(wide, "w") as fh: fh.write("日本 abc\n")
    b5.send("open", path=wide); b5.settle(0.3)
    b5.keys("0fa")
    c = b5.last["cursor"]
    check("cursor: cell and character differ past wide characters",
          c["col"] == 5 and c.get("ch") == 3, c)

    # a directory renamed in the tree: buffers inside it follow
    b5.send("open", path=sfile); b5.settle(0.3)
    moved = os.path.join(proj, "moved")
    os.rename(os.path.join(proj, "sub"), moved)
    ask(b5, "renamed", **{"from": os.path.join(proj, "sub"), "to": moved})
    check("a renamed directory takes its buffers along",
          ask(b5, "cmd", cmd="lua assert(vim.api.nvim_buf_get_name(0) == " + json.dumps(os.path.join(moved, "s.txt")) + ")") is True)

    # ── 2026-10-04 batch 2: guides, outline, root save, disk, drop, … ────
    b6 = Bridge(tmp, "t6")
    b6.send("resize", rows=12, cols=60); b6.settle(0.3)
    def ask6(method, **params): return ask(b6, method, **params)

    # indent guides: every shiftwidth inside the indent; a blank line takes
    # the deeper of its neighbours
    gfile = os.path.join(tmp, "guides.txt")
    with open(gfile, "w") as fh: fh.write("fn a {\n    x\n        y\n\n    z\n}\n")
    b6.send("open", path=gfile); b6.settle(0.3)
    ig = [b6.rows[i].get("ig") for i in range(6)]
    check("guides: one level, two levels, a blank between", ig == [None, [0], [0, 4], [0, 4], [0], None], ig)
    b6.keys("3G")
    check("scope: the block the cursor's line sits in",
          b6.last.get("scope") == {"col": 4, "first": 3, "last": 4}, b6.last.get("scope"))
    b6.keys("gg")
    check("scope: on an opener, the block it opens",
          b6.last.get("scope") == {"col": 0, "first": 2, "last": 5}, b6.last.get("scope"))
    ask6("options", indentGuides=False); b6.settle()
    check("guides: off in the settings, none sent", all(not (r or {}).get("ig") for r in b6.rows), b6.rows[1])
    ask6("options", indentGuides=True); b6.settle()

    # the outline, from the text when no language server is attached
    md = os.path.join(tmp, "notes.md")
    with open(md, "w") as fh: fh.write("# A\ntext\n## B\nmore\n# C\n")
    b6.send("open", path=md); b6.settle(0.3)
    syms = ask6("symbols")
    check("outline: markdown headings, nested",
          [(s["name"], s["depth"], s["line"]) for s in syms] == [("A", 0, 1), ("B", 1, 3), ("C", 0, 5)], syms)
    b6.keys("4G"); b6.settle()
    st6 = [f["status"] for f in b6.frames if f.get("status")]
    check("breadcrumb: the headings the cursor is under",
          st6 and st6[-1].get("crumbs") == ["A", "B"], st6[-1:] and st6[-1].get("crumbs"))

    # spelling: in prose every word; z= sends suggestions
    with open(md, "w") as fh: fh.write("teh cat\n")
    b6.send("cmd", cmd="edit!"); b6.settle(0.3)
    b6.send("cmd", cmd="setlocal spell"); b6.settle(0.3)
    check("spell: a misspelled word is curled", b6.style_at(0, 1).get("c") is True, b6.rows[0])
    check("spell: a good word is not", b6.style_at(0, 5).get("c") is not True, b6.rows[0])
    b6.keys("gg"); b6.events.clear(); b6.keys("z=")
    sp = [e for e in b6.events if e.get("event") == "spell"]
    check("z=: suggestions come to plato", sp and sp[0]["word"] == "teh" and "the" in sp[0]["items"], sp)
    b6.send("cmd", cmd="setlocal nospell"); b6.settle()

    # a file this user cannot write: plato asks, and nothing is written
    # until it is answered
    ro = os.path.join(tmp, "ro.txt")
    with open(ro, "w") as fh: fh.write("locked\n")
    os.chmod(ro, 0o444)
    b6.send("open", path=ro); b6.settle(0.3)
    st6 = [f["status"] for f in b6.frames if f.get("status")]
    check("root: a file not ours is marked", st6 and st6[-1].get("root") is True, st6[-1:])
    check("root: and not read-only (plato writes it)", b6.last["readonly"] is False)
    b6.keys("Anew<Esc>"); b6.events.clear()
    for k in (":", "w", "<CR>"): b6.keys(k)
    b6.settle(0.3)
    asks = [e for e in b6.events if e.get("event") == "ask"]
    check("root: :w asks, with Save as root", asks and asks[0]["choices"][0]["key"] == "s", asks)
    check("root: nothing written before the answer", open(ro).read() == "locked\n")
    if asks: ask6("answer", ask=asks[0]["ask"], choice="")
    check("root: dismissed, still modified", ask6("cmd", cmd="lua assert(vim.bo.modified)") is True)
    b6.send("cmd", cmd="bdelete!"); b6.settle()
    os.chmod(ro, 0o644)

    # a file changed on disk: untouched, read again; edited, asked
    dfile = os.path.join(tmp, "disk.txt")
    with open(dfile, "w") as fh: fh.write("one\n")
    b6.send("open", path=dfile); b6.settle(0.3)
    time.sleep(1.1)
    with open(dfile, "w") as fh: fh.write("two\n")
    b6.send("cmd", cmd="checktime"); b6.settle(0.3)
    check("disk: an untouched buffer is read again", b6.text()[:1] == ["two"], b6.text())
    b6.keys("Ax<Esc>")
    time.sleep(1.1)
    with open(dfile, "w") as fh: fh.write("three\n")
    b6.events.clear()
    b6.send("cmd", cmd="checktime"); b6.settle(0.3)
    asks = [e for e in b6.events if e.get("event") == "ask"]
    check("disk: edited and changed, asked", asks and [c["key"] for c in asks[0]["choices"]] == ["r", "m", "d"], asks)
    if asks: ask6("answer", ask=asks[0]["ask"], choice="r"); b6.settle(0.3)
    check("disk: Reload takes the file's text", b6.text()[:1] == ["three"] and b6.last["modified"] is False, b6.text())

    # files dropped on the window: opened, a directory passed over
    d1, d2 = os.path.join(tmp, "d1.txt"), os.path.join(tmp, "d2.txt")
    for f in (d1, d2):
        with open(f, "w") as fh: fh.write(f + "\n")
    ids = ask6("dropped", paths=[d1, tmp, d2]); b6.settle(0.3)
    check("drop: the files open, the directory does not", isinstance(ids, list) and len(ids) == 2, ids)
    check("drop: the last one is shown", b6.last["file"].endswith("d2.txt"), b6.last["file"])

    # the start card's lists, and typewriter
    sc = ask6("startCard")
    check("start card: three lists", isinstance(sc, dict) and all(k in sc for k in ("recent", "pins", "projects")), sc)
    ask6("options", typewriter=True)
    check("typewriter: the cursor's line held mid-window", ask6("cmd", cmd="lua assert(vim.wo.scrolloff == 999)") is True)
    ask6("options", scrollOff=5)
    check("typewriter: kept through a scrolloff change", ask6("cmd", cmd="lua assert(vim.wo.scrolloff == 999)") is True)
    ask6("options", typewriter=False)
    check("typewriter: off gives the setting back", ask6("cmd", cmd="lua assert(vim.wo.scrolloff ~= 999)") is True)

    # a file past the large threshold opens with the extras off
    ask6("options", largeFileMB=1)
    big = os.path.join(tmp, "big.lua")
    with open(big, "w") as fh: fh.write(("local x = '#ff0000' -- teh\n" * 60000))
    b6.send("open", path=big); b6.settle(0.5)
    st6 = [f["status"] for f in b6.frames if f.get("status")]
    check("large: marked in the status line", st6 and st6[-1].get("large") is True, st6[-1:] and st6[-1].get("large"))
    check("large: no treesitter", ask6("cmd", cmd="lua assert(not vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()])") is True)
    check("large: no colour codes painted", not b6.style_at(0, 11).get("bg"), b6.rows[0])
    # a slow request while nvim waits for the rest of a command (" then a
    # focus change's :checktime) must not wedge the keys behind it
    b6.send("input", keys='"'); b6.settle()
    b6.send("cmd", cmd="silent! checktime")
    b6.frames.clear()
    b6.send("input", keys="<Esc>"); b6.settle(0.4)
    check("mid-command: a slow request does not hold the keys that finish it", len(b6.frames) > 0, len(b6.frames))
    b6.frames.clear(); b6.keys("j"); b6.settle(0.3)
    check("mid-command: and the keys after it still land", len(b6.frames) > 0)
    b6.send("quit"); b6.proc.wait(timeout=5)

    # paths are offered as they are typed (paths.lua), each with its file
    b7 = Bridge(tmp, "b7")
    os.makedirs(os.path.join(tmp, "pc", "inner"))
    for n in ("todo.txt", "tools.md"): open(os.path.join(tmp, "pc", n), "w").write("x\n")
    pdoc = os.path.join(tmp, "pc", "here.txt"); open(pdoc, "w").write("\n")
    b7.send("resize", rows=12, cols=60); b7.send("open", path=pdoc); b7.settle(0.4)
    b7.events.clear()
    b7.keys("i./t")
    pum = [e for e in b7.events if e.get("event") == "pum" and e.get("shown")]
    got = [(i["word"], i.get("path")) for i in pum[-1]["items"]] if pum else []
    check("paths: ./t offers the files beside this one",
          got == [("todo.txt", os.path.join(tmp, "pc", "todo.txt")), ("tools.md", os.path.join(tmp, "pc", "tools.md"))], got)
    b7.events.clear()
    b7.keys("<BS>")
    pum = [e for e in b7.events if e.get("event") == "pum" and e.get("shown")]
    check("paths: a directory first, with its slash",
          bool(pum) and pum[-1]["items"][0]["word"] == "inner/" and pum[-1]["items"][0]["kind"] == "dir",
          pum[-1:] and pum[-1]["items"][:2])
    check("paths: words are not paths", all(i.get("path") is None for i in pum[-1]["items"] if i.get("kind") not in ("dir", "file")) if pum else False)
    # <C-Space>: the menu on demand, with no letter typed; again closes it
    b7.keys("<Esc>Goalphabet<Esc>"); b7.events.clear()
    b7.keys("o<C-Space>")
    pum = [e for e in b7.events if e.get("event") == "pum"]
    check("ctrl-space: a menu on a blank line", bool(pum) and pum[-1].get("shown") and len(pum[-1]["items"]) > 0, pum[-1:])
    b7.keys("<C-Space>")
    pum = [e for e in b7.events if e.get("event") == "pum"]
    check("ctrl-space: again closes it", bool(pum) and not pum[-1].get("shown"), pum[-1:])
    # a frame per <BS> straight away: 'autocompletedelay' held each one back
    # 40 ms, and a held backspace fell behind its own key repeat
    b7.keys("<Esc>Ohello world<Esc>A")
    waits = []
    for _ in range(6):
        t0 = time.monotonic()
        b7.send("input", keys="<BS>")
        while True:
            select.select([b7.s], [], [], 1)
            ev = json.loads(b7.f.readline())
            if ev.get("event") == "view": break
        waits.append((time.monotonic() - t0) * 1000)
        b7.settle(0.05)
    waits.sort()
    check("backspace: its frame comes without autocomplete's delay", waits[len(waits) // 2] < 30, waits)
    b7.send("quit"); b7.proc.wait(timeout=5)

    # insert mode's GUI keys (cua.lua), one key per request as plato sends them
    b8 = Bridge(tmp, "cua")
    cdoc = os.path.join(tmp, "cua.txt"); open(cdoc, "w").write("hello world foo\nsecond line\n")
    b8.send("resize", rows=12, cols=60); b8.send("open", path=cdoc); b8.settle(0.4)
    def cua(*ks):
        for k in ks: b8.keys(k)
    cua("g", "g", "0", "w", "i", "<S-Right>", "<S-Right>")
    sel = [x for x in b8.rows[0]["s"] if b8.styles.get(x[2], {}).get("bg") == MAGENTA]
    check("shift right twice: two characters selected, drawn as a selection",
          sel and sel[0][0] == 6 and sum(x[1] for x in sel) == 2, b8.rows[0]["s"])
    cua("X")
    check("typing replaces the selection, in insert mode",
          b8.text()[0] == "hello Xrld foo" and b8.last["mode"].startswith("i"), (b8.text(), b8.last["mode"]))
    cua("<S-Left>", "<S-Right>", "Y")
    check("back onto the anchor is no selection", b8.text()[0] == "hello XYrld foo", b8.text())
    cua("<C-S-Right>", "<Left>", "Z")
    check("ctrl shift right a word; left puts it down at its start", b8.text()[0] == "hello XYZrld foo", b8.text())
    cua("<C-BS>")
    check("ctrl backspace deletes a word back", b8.text()[0] == "hello rld foo", b8.text())
    cua("<Home>", "<S-Left>", "Q")
    check("shift left on the first column takes nothing", b8.text()[0] == "Qhello rld foo", b8.text())
    cua("<Down>", "<Home>", "<S-Left>", "<BS>")
    check("shift left at a line's start wraps onto the line above", b8.text()[0] == "Qhello rld foosecond line", b8.text())
    cua("<Esc>", "0", "v", "l", "d")
    check("and normal mode's v is inclusive again afterwards", b8.text()[0] == "ello rld foosecond line", b8.text())
    b8.send("quit"); b8.proc.wait(timeout=5)

    # ── 2026-10-05 polish: pairs, rainbow, folds, pills, selection, pulse, puts
    b9 = Bridge(tmp, "polish")
    pdoc = os.path.join(tmp, "polish.js")
    open(pdoc, "w").write("function f(a) {\n  if (a) { return [a, (a)]; }\n  return \"(x\";\n}\nlet a = 1;\nlet b = 2;\nlet c = 3;\nvalue value\n")
    b9.send("resize", rows=14, cols=60); b9.send("open", path=pdoc); b9.settle(0.4)
    def cellOf(row, ch, nth=0):
        t = b9.rows[row]["t"]; i = -1
        for _ in range(nth + 1): i = t.index(ch, i + 1)
        return i
    # the bracket under the cursor and its partner are both outlined
    b9.keys("g"); b9.keys("g"); b9.keys("f"); b9.keys("{")
    check("pair: the brace under the cursor is outlined", cellOf(0, "{") in (b9.rows[0].get("m") or []), b9.rows[0].get("m"))
    check("pair: and its partner three lines down", b9.rows[3].get("m") == [0], b9.rows[3].get("m"))
    b9.keys("0")
    check("pair: none off a bracket", not b9.rows[0].get("m") and not b9.rows[3].get("m"), (b9.rows[0].get("m"), b9.rows[3].get("m")))
    # rainbow: a level deeper is another colour; a bracket in a string is not one
    outer = b9.style_at(0, cellOf(0, "{")).get("fg")
    inner = b9.style_at(1, cellOf(1, "(")).get("fg")
    check("rainbow: nested brackets differ in colour", outer and inner and outer != inner, (outer, inner))
    check("rainbow: a bracket in a string keeps the string's colour",
          b9.style_at(2, cellOf(2, "(")).get("fg") == b9.style_at(2, cellOf(2, "x")).get("fg"))
    b9.send("options", rainbowBrackets=False); b9.settle()
    check("rainbow: off, a bracket is punctuation again", b9.style_at(1, cellOf(1, "(")).get("fg") != inner)
    b9.send("options", rainbowBrackets=True); b9.settle()
    # a closed fold is its first line and a pill counting the lines
    b9.keys("5"); b9.keys("G"); b9.keys("z"); b9.keys("f"); b9.keys("j")
    fr = next(r for r in b9.rows if r and r["f"])
    check("fold: its first line, then the count", fr["t"].startswith("let a = 1;") and fr["t"].endswith("2 lines"), fr["t"])
    check("fold: the pill's cells", fr.get("fc") and fr["t"][fr["fc"][0]:].startswith("\u22ef"), fr.get("fc"))
    b9.keys("z"); b9.keys("o")
    # a diagnostic at the line's end is a pill of its severity
    b9.send("cmd", cmd='lua vim.diagnostic.set(vim.api.nvim_create_namespace("t"), 0, {{lnum=4,col=0,message="short",severity=2},{lnum=5,col=0,message=string.rep("long ",20),severity=1}})')
    b9.settle(0.3)
    vt = b9.rows[4].get("vt")
    check("pill: a warning's", vt and vt[2] == "w" and "short" in b9.rows[4]["t"][vt[0]:vt[1]] and not vt[3], vt)
    vt = b9.rows[5].get("vt")
    check("pill: one cut by the edge says so, and ends in an ellipsis",
          vt and vt[2] == "e" and vt[3] and b9.rows[5]["t"].endswith("\u2026"), (vt, b9.rows[5]["t"]))
    # the selection's part of each row, for one shape
    b9.keys("g"); b9.keys("g"); b9.keys("w"); b9.keys("v"); b9.keys("j")
    check("selection: a part on each row", b9.rows[0].get("sl") and b9.rows[1].get("sl") and not b9.rows[2].get("sl"),
          [b9.rows[i].get("sl") for i in range(3)])
    check("selection: from the cursor's start to the line's end", b9.rows[0]["sl"][0] == 9, b9.rows[0].get("sl"))
    b9.keys("<Esc>")
    # a search jump pulses; a plain motion onto a match does not
    b9.keys("/value<CR>")
    pulses = [f.get("pulse") for f in b9.frames[-6:] if f.get("pulse")]
    check("pulse: a confirmed search", pulses and pulses[-1]["len"] == 5, pulses)
    b9.frames.clear(); b9.keys("n")
    check("pulse: n", any(f.get("pulse") for f in b9.frames), [f.get("pulse") for f in b9.frames])
    b9.frames.clear(); b9.keys("0")
    check("pulse: not a plain motion", not any(f.get("pulse") for f in b9.frames))
    # a paste lights what it brought; a plain edit does not
    b9.keys("g"); b9.keys("g"); b9.keys("y"); b9.keys("y"); b9.events.clear()
    b9.keys("p")
    ar = [e for e in b9.events if e.get("event") == "flash" and e.get("kind") == "arrive"]
    check("arrive: p flashes the line it put", len(ar) == 1 and ar[0]["cells"][0]["row"] == 1, ar)
    b9.events.clear(); b9.keys("x")
    check("arrive: x does not", not [e for e in b9.events if e.get("kind") == "arrive"])
    b9.send("quit"); b9.proc.wait(timeout=5)

    # two new buffers rescued in the same second are two files, not one
    rdir = os.path.join(STATE, "rescue")
    before = len(os.listdir(rdir)) if os.path.isdir(rdir) else 0
    for word in ("first", "second"):
        b5.send("cmd", cmd="enew"); b5.settle()
        b5.keys("i" + word + "<Esc>")
    b5.send("quit"); b5.proc.wait(timeout=5)
    after = len(os.listdir(rdir)) if os.path.isdir(rdir) else 0
    check("two untitled buffers rescued side by side", after - before == 2, (before, after))

finally:
    for p in ("b", "b2", "b3", "b4", "b5", "b6", "b7", "b8", "b9"):
        br = globals().get(p)
        if br and br.proc.poll() is None: br.proc.kill()
    shutil.rmtree(tmp, ignore_errors=True)
    shutil.rmtree(STATE, ignore_errors=True)
    shutil.rmtree(os.path.expanduser("~/.local/share/plato-test"), ignore_errors=True)

print(f"plato-bridge: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
