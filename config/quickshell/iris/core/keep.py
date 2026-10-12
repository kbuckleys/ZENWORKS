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
        self._db.execute("CREATE TABLE IF NOT EXISTS zoom (site TEXT PRIMARY KEY, factor REAL NOT NULL)")
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

    @Slot(str, int, result="QVariantList")
    def suggest(self, typed, limit):
        t = typed.strip().lower()
        if not t:
            return []
        like = "%" + t.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
        rows = self._db.execute(
            "SELECT url, title, visits, last FROM pages WHERE url LIKE ? ESCAPE '\\'"
            " OR title LIKE ? ESCAPE '\\' ORDER BY last DESC LIMIT 400", (like, like)).fetchall()
        now = time.time()
        scored = sorted(((rank(u, ti, v, la, t, now), u, ti) for u, ti, v, la in rows), reverse=True)
        return [{"url": u, "title": ti} for s, u, ti in scored[:max(1, limit)] if s > 0]

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
