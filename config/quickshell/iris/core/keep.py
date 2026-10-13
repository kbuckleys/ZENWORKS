# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# WHAT IRIS KEEPS — never anything from a cloak tab (the window never hands
# one over).
#
#   history   ~/.local/share/quickshell/iris/history.sqlite: a row per page
#             (url, title, visits, last visit), for the address line's
#             suggestions. SQLite because it is tens of thousands of rows
#             asked "which match this, best first" on every keystroke; WAL
#             and synchronous=NORMAL, so a visit costs well under a ms.
#   zoom      in history.sqlite too: a site's zoom, kept when it is not 100%
#   session   session.json beside it: the open tabs, in order, and which was
#             looked at — written whole and atomically, read once at launch.
#
# rank() is the one judgement here, kept a pure function so oracle/tests/
# iris-core.py can hold it to its word.

import json, math, os, sqlite3, time

from PySide6.QtCore import QObject, Slot

# addresses not worth remembering: blank pages, inline documents, chrome's own
SKIP = ("about:", "data:", "chrome:", "blob:", "javascript:")


def rank(url, title, visits, last, typed, now):
    """How well a remembered page answers what is being typed (0 = not)."""
    t = typed.strip().lower()
    if not t:
        return 0.0
    u, ti = url.lower(), (title or "").lower()
    bare = u.split("://", 1)[-1]
    bare = bare[4:] if bare.startswith("www.") else bare
    if bare.startswith(t):
        fit = 4.0                  # the address as typed: the likeliest answer
    elif any(w.startswith(t) for w in ti.split()):
        fit = 2.0
    elif t in u or t in ti:
        fit = 1.0
    else:
        return 0.0
    age_days = max(0.0, (now - last) / 86400.0)
    # frecency: often counts, recently counts more; a week halves it
    return fit * (1.0 + math.log1p(visits)) * math.pow(0.5, age_days / 7.0)


class History(QObject):
    def __init__(self, path, parent=None):
        super().__init__(parent)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self._db = sqlite3.connect(path)
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.execute("PRAGMA synchronous=NORMAL")
        self._db.execute("CREATE TABLE IF NOT EXISTS pages (url TEXT PRIMARY KEY, title TEXT,"
                         " visits INTEGER NOT NULL DEFAULT 0, last INTEGER NOT NULL DEFAULT 0)")
        self._db.execute("CREATE INDEX IF NOT EXISTS pages_last ON pages(last)")
        # the page's favicon, as Qt WebEngine names it (image://favicon/…),
        # for the line's suggestions (a history from before had none)
        if "icon" not in [r[1] for r in self._db.execute("PRAGMA table_info(pages)")]:
            self._db.execute("ALTER TABLE pages ADD COLUMN icon TEXT NOT NULL DEFAULT ''")
        self._db.execute("CREATE TABLE IF NOT EXISTS zoom (site TEXT PRIMARY KEY, factor REAL NOT NULL)")
        self._db.execute("CREATE TABLE IF NOT EXISTS sites (host TEXT NOT NULL, key TEXT NOT NULL,"
                         " value INTEGER NOT NULL, PRIMARY KEY (host, key))")
        self._db.execute("CREATE TABLE IF NOT EXISTS handlers (scheme TEXT NOT NULL, origin TEXT NOT NULL,"
                         " allowed INTEGER NOT NULL, PRIMARY KEY (scheme, origin))")
        self._db.commit()

    # ── A SITE'S OFFER TO OPEN A KIND OF LINK (mailto: …) ───────────────
    # Chromium in Qt keeps the answer in memory only, and a mail site offers
    # again on every load: asked once, the answer is kept here and given for
    # it ever after (-1: never asked).
    # ── A SITE'S OWN SETTINGS (the line's site bubble) ──────────────────
    # host → { key: 0 | 1 } for what was set by hand: "shield" (content
    # blocking), "autoplay", "popups". Not there = the default.
    @Slot(str, result="QVariantMap")
    def site(self, host):
        return {k: int(v) for k, v in self._db.execute(
            "SELECT key, value FROM sites WHERE host = ?", (host,)).fetchall()} if host else {}

    @Slot(str, str, int)
    def setSite(self, host, key, value):
        if not host:
            return
        if value < 0:
            self._db.execute("DELETE FROM sites WHERE host = ? AND key = ?", (host, key))
        else:
            self._db.execute("INSERT INTO sites(host, key, value) VALUES (?, ?, ?)"
                             " ON CONFLICT(host, key) DO UPDATE SET value = excluded.value", (host, key, value))
        self._db.commit()

    def hosts_with(self, key, value):
        return [h for (h,) in self._db.execute("SELECT host FROM sites WHERE key = ? AND value = ?", (key, value))]

    @Slot(str, str, result=int)
    def handlerAnswer(self, scheme, origin):
        row = self._db.execute("SELECT allowed FROM handlers WHERE scheme = ? AND origin = ?",
                               (scheme, origin)).fetchone()
        return int(row[0]) if row else -1

    @Slot(str, str, bool)
    def keepHandler(self, scheme, origin, allowed):
        self._db.execute("INSERT INTO handlers(scheme, origin, allowed) VALUES (?, ?, ?)"
                         " ON CONFLICT(scheme, origin) DO UPDATE SET allowed = excluded.allowed",
                         (scheme, origin, 1 if allowed else 0))
        self._db.commit()

    @Slot(str, result=float)
    def zoomFor(self, site):
        row = self._db.execute("SELECT factor FROM zoom WHERE site = ?", (site,)).fetchone() if site else None
        return float(row[0]) if row else 1.0

    @Slot(str, float)
    def keepZoom(self, site, factor):
        if not site:
            return
        if abs(factor - 1.0) < 0.001:
            self._db.execute("DELETE FROM zoom WHERE site = ?", (site,))
        else:
            self._db.execute("INSERT INTO zoom(site, factor) VALUES (?, ?)"
                             " ON CONFLICT(site) DO UPDATE SET factor = excluded.factor", (site, factor))
        self._db.commit()

    @Slot(str, str)
    def visit(self, url, title):
        if not url or url.startswith(SKIP):
            return
        self._db.execute(
            "INSERT INTO pages(url, title, visits, last) VALUES (?, ?, 1, ?)"
            " ON CONFLICT(url) DO UPDATE SET visits = visits + 1, last = excluded.last,"
            " title = CASE WHEN excluded.title != '' THEN excluded.title ELSE title END",
            (url, title or "", int(time.time())))
        self._db.commit()

    @Slot(str, str)
    def retitle(self, url, title):
        if url and title and not url.startswith(SKIP):
            self._db.execute("UPDATE pages SET title = ? WHERE url = ?", (title, url))
            self._db.commit()

    @Slot(str, str)
    def setIcon(self, url, icon):
        if url and not url.startswith(SKIP):
            self._db.execute("UPDATE pages SET icon = ? WHERE url = ?", (icon or "", url))
            self._db.commit()

    @Slot(str, int, result="QVariantList")
    def suggest(self, typed, limit):
        t = typed.strip().lower()
        if not t:
            return []
        like = "%" + t.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
        rows = self._db.execute(
            "SELECT url, title, visits, last, icon FROM pages WHERE url LIKE ? ESCAPE '\\'"
            " OR title LIKE ? ESCAPE '\\' ORDER BY last DESC LIMIT 400", (like, like)).fetchall()
        now = time.time()
        scored = sorted(((rank(u, ti, v, la, t, now), u, ti, ic) for u, ti, v, la, ic in rows), reverse=True)
        return [{"url": u, "title": ti, "icon": ic} for s, u, ti, ic in scored[:max(1, limit)] if s > 0]

    def close(self):
        self._db.close()


class Session(QObject):
    def __init__(self, path, parent=None):
        super().__init__(parent)
        self._path = path

    @Slot(result=str)
    def load(self):
        try:
            with open(self._path, encoding="utf-8") as f:
                return f.read()
        except OSError:
            return ""

    @Slot(str)
    def save(self, text):
        tmp = self._path + ".part"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, self._path)
