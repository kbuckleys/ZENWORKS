#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# IRIS CORE TESTS — iris/core without a window: the history's ranking and
# store, the session file, and the single-instance door (a live handover and
# a socket left by a dead iris). A throwaway XDG_RUNTIME_DIR and data
# directory, so the user's own iris is never touched.
#
#   python3 oracle/tests/iris-core.py

import os
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TMP = tempfile.mkdtemp(prefix="iris-test-")
os.environ["XDG_RUNTIME_DIR"] = TMP
os.environ["XDG_CACHE_HOME"] = os.path.join(TMP, "cache")
sys.path.insert(0, os.path.join(ROOT, "iris", "core"))

from PySide6.QtCore import QCoreApplication, QTimer  # noqa: E402
import keep  # noqa: E402
import door  # noqa: E402

fails, count = [], 0


def eq(name, got, want):
    global count
    count += 1
    if got != want:
        fails.append(f"{name}\n      want {want!r}\n      got  {got!r}")
    else:
        print("  ok  " + name)


now = time.time()
day = 86400
# ── rank ────────────────────────────────────────────────────────────────
eq("nothing typed ranks nothing", keep.rank("https://a.org/", "A", 3, now, "", now), 0.0)
eq("no match ranks nothing", keep.rank("https://a.org/", "Alpha", 3, now, "zzz", now), 0.0)
eq("the address as typed beats a title word",
   keep.rank("https://arch.org/", "x", 1, now, "arch", now) > keep.rank("https://x.org/", "Arch news", 1, now, "arch", now), True)
eq("www. is no part of what is typed",
   keep.rank("https://www.github.com/", "GitHub", 1, now, "git", now) > keep.rank("https://x.org/git", "", 1, now, "git", now), True)
eq("often beats once", keep.rank("https://a.org/", "", 50, now, "a.o", now) > keep.rank("https://a.org/", "", 1, now, "a.o", now), True)
eq("a week halves it", round(keep.rank("https://a.org/", "", 1, now - 7 * day, "a.o", now)
                             / keep.rank("https://a.org/", "", 1, now, "a.o", now), 3), 0.5)

# ── history ─────────────────────────────────────────────────────────────
h = keep.History(os.path.join(TMP, "data", "history.sqlite"))
h.visit("https://wiki.archlinux.org/title/Iris", "Iris - ArchWiki")
h.visit("https://wiki.archlinux.org/title/Iris", "")
h.visit("https://archlinux.org/", "Arch Linux")
h.visit("about:blank", "")
h.visit("data:text/html,x", "x")
eq("blank and inline pages are not kept",
   [r["url"] for r in h.suggest("a", 10) if r["url"].startswith(("about:", "data:"))], [])
eq("a visit without a title keeps the title it had",
   h.suggest("iris", 5)[0]["title"], "Iris - ArchWiki")
eq("typed host first", h.suggest("archlinux.org", 5)[0]["url"], "https://archlinux.org/")
h.retitle("https://archlinux.org/", "Arch Linux — home")
eq("retitled", h.suggest("arch", 5)[0]["title"] in ("Arch Linux — home", "Iris - ArchWiki"), True)
eq("a % is a literal", h.suggest("%", 5), [])
eq("nothing typed, nothing suggested", h.suggest("  ", 5), [])
h.close()

# ── session ─────────────────────────────────────────────────────────────
s = keep.Session(os.path.join(TMP, "data", "session.json"))
eq("no session yet", s.load(), "")
s.save('{"tabs": [1]}')
eq("a session saved is the session loaded", s.load(), '{"tabs": [1]}')
eq("written whole, nothing left over", os.path.exists(os.path.join(TMP, "data", "session.json.part")), False)

# ── the door ────────────────────────────────────────────────────────────
app = QCoreApplication([])
eq("no iris up: nobody answers", door.knock("https://a.org"), False)
d = door.Door()
got = []
d.asked.connect(lambda u, c: got.append((u, c)))


def ask():
    # from another process, as a second `iris` would — on a thread, so this
    # one's event loop is free to answer it
    import subprocess, threading
    def run():
        r = subprocess.run([sys.executable, "-I", "-c",
                            "import sys; sys.path.insert(0, %r); import door; "
                            "print(door.knock('https://b.org', True))" % os.path.join(ROOT, "iris", "core")],
                           capture_output=True, text=True, env=dict(os.environ))
        got.append(("knock said", r.stdout.strip()))
        QTimer.singleShot(0, app.quit)
    threading.Thread(target=run, daemon=True).start()


QTimer.singleShot(50, ask)
QTimer.singleShot(8000, app.quit)
app.exec()
eq("the knock was answered", ("knock said", "True") in got, True)
eq("a running iris takes the request", ("https://b.org", True) in got, True)
d.close()
# a dead iris' socket: a file nobody listens on
import socket  # noqa: E402
dead = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
dead.bind(door.PATH)
dead.close()
eq("a dead iris' socket answers nobody", door.knock("https://c.org"), False)
d2 = door.Door()
eq("and the next iris listens there anyway", d2._server.isListening(), True)
d2.close()

# ── the shield: a page's hiding rules and scriptlets ───────────────────────
import shield  # noqa: E402
os.makedirs(shield.LISTS_DIR, exist_ok=True)
with open(shield._list_path("easylist"), "w") as f:
    f.write("example.org##.sponsored\nexample.org##+js(acs, Promise, adblock)\n##.generic-ad\n@@||example.net^$generichide\n")
with open(shield._list_path(shield.SCRIPTLETS[0]), "w") as f:
    f.write("/// abort-current-script.js\n/// alias acs.js\n(function() {\n    const target = '{{1}}';\n    const needle = '{{2}}';\n})();\n")
sh = shield.Shield()
c = sh.cosmetic("https://example.org/page")
eq("a site's hide rule, as a style sheet", ".sponsored{display:none!important}" in c["css"], True)
eq("its scriptlet, its arguments filled in", "Promise" in c["script"] and "adblock" in c["script"], True)
eq("the generic rules apply", c["generic"], True)
eq("a generic rule, for the class that calls for it", sh.generic("https://example.org/page", ["generic-ad", "other"], []),
   ".generic-ad{display:none!important}")
eq("nothing for classes no rule names", sh.generic("https://example.org/page", ["plain"], []), "")
eq("a site exempted from generic rules says so", sh.cosmetic("https://example.net/")["generic"], False)
eq("not a web page: nothing", sh.cosmetic("about:blank"), {"css": "", "script": "", "generic": False})

# ── HTTPS first ─────────────────────────────────────────────────────────────
from PySide6.QtCore import QUrl  # noqa: E402
up = lambda u: (lambda r: r.toString() if r is not None else None)(sh.upgrade(QUrl(u)))
eq("plain http upgraded", up("http://example.com/a?b=1"), "https://example.com/a?b=1")
eq("port 80 dropped with it", up("http://example.com:80/"), "https://example.com/")
eq("another port kept", up("http://example.com:8080/"), "https://example.com:8080/")
eq("https left", up("https://example.com/"), None)
eq("this machine left", up("http://localhost:3000/"), None)
eq("the local network left", up("http://192.168.1.1/"), None)
eq("a .local name left", up("http://nas.local/"), None)
eq("a bare intranet name left", up("http://printer/"), None)
sh.allow_plain("old.example.com")
eq("a site let through stays plain", up("http://old.example.com/"), None)

print(f"\niris core: {count - len(fails)} passed, {len(fails)} failed")
for f in fails:
    print("  FAIL " + f)
sys.exit(1 if fails else 0)
