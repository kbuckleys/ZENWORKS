# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE SHIELD — iris' content filter. python-adblock (adblock-rust underneath,
# so the matching itself is native) behind Qt WebEngine's request interceptor.
# One Shield serves every profile, cloak included: filtering is never off.
#
#   lists      the filter lists, kept in ~/.cache/quickshell/iris/lists
#   engine     compiled once and saved as engine.dat; a launch deserializes
#              that (tens of ms) instead of parsing the lists again
#   refresh    lists older than REFRESH are fetched on a thread after the
#              window is up, and the new engine swapped in whole — a page
#              never sees half an engine
#
# THE INTERCEPTOR RUNS ON THE GUI THREAD (Qt 6), once per request. Keep it to
# the lookup: no I/O, no logging per request, nothing that allocates much.

import os, threading, time, urllib.request

import adblock
from PySide6.QtWebEngineCore import QWebEngineUrlRequestInterceptor, QWebEngineUrlRequestInfo

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                     "quickshell", "iris")
LISTS_DIR = os.path.join(CACHE, "lists")
ENGINE = os.path.join(CACHE, "engine.dat")
REFRESH = 4 * 24 * 3600

# name → url. uBlock's own lists ride on EasyList's syntax; what this engine
# version does not understand it skips, rule by rule.
LISTS = {
    "easylist":    "https://easylist.to/easylist/easylist.txt",
    "easyprivacy": "https://easylist.to/easylist/easyprivacy.txt",
    "ublock":      "https://ublockorigin.github.io/uAssets/filters/filters.txt",
    "ublock-privacy": "https://ublockorigin.github.io/uAssets/filters/privacy.txt",
    "peter-lowe":  "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=0&mimetype=plaintext",
}

RT = QWebEngineUrlRequestInfo.ResourceType
# Qt's resource types → adblock's request types. Anything missing is "other".
KINDS = {
    RT.ResourceTypeMainFrame: "document",
    RT.ResourceTypeSubFrame: "subdocument",
    RT.ResourceTypeStylesheet: "stylesheet",
    RT.ResourceTypeScript: "script",
    RT.ResourceTypeImage: "image",
    RT.ResourceTypeFontResource: "font",
    RT.ResourceTypeObject: "object",
    RT.ResourceTypeMedia: "media",
    RT.ResourceTypeWorker: "script",
    RT.ResourceTypeSharedWorker: "script",
    RT.ResourceTypeServiceWorker: "script",
    RT.ResourceTypePrefetch: "other",
    RT.ResourceTypeFavicon: "image",
    RT.ResourceTypeXhr: "xmlhttprequest",
    RT.ResourceTypePing: "ping",
    RT.ResourceTypeCspReport: "csp_report",
    RT.ResourceTypePluginResource: "object",
    RT.ResourceTypeWebSocket: "websocket",
}


def _list_path(name):
    return os.path.join(LISTS_DIR, name + ".txt")


def _compile():
    """An engine from whatever lists are on disk (None when there are none)."""
    fs = adblock.FilterSet(debug=False)
    found = False
    for name in LISTS:
        try:
            with open(_list_path(name), encoding="utf-8", errors="replace") as f:
                fs.add_filter_list(f.read())
            found = True
        except OSError:
            pass
    return adblock.Engine(fs, optimize=True) if found else None


def _fetch(name, url):
    req = urllib.request.Request(url, headers={"User-Agent": "iris"})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
    if len(body) < 1024:            # an error page, not a list
        raise ValueError(f"{name}: {len(body)} bytes")
    tmp = _list_path(name) + ".part"
    with open(tmp, "wb") as f:
        f.write(body)
    os.replace(tmp, _list_path(name))


class Shield(QWebEngineUrlRequestInterceptor):
    def __init__(self, parent=None):
        super().__init__(parent)
        os.makedirs(LISTS_DIR, exist_ok=True)
        self.engine = None
        self.seen = 0
        self.blocked = 0
        self.spent_ns = 0
        self.worst_ns = 0
        self._load()

    # ── engine ──────────────────────────────────────────────────────────
    def _load(self):
        t = time.perf_counter()
        e = adblock.Engine(adblock.FilterSet(debug=False))
        try:
            e.deserialize_from_file(ENGINE)
            self.engine, how = e, "saved"
        except Exception:
            self.engine, how = _compile(), "compiled"
            if self.engine:
                self.engine.serialize_to_file(ENGINE)
        # The engine's first lookup builds its shared tables (~17 ms measured);
        # pay that here, before a page is waiting on it.
        if self.engine:
            self.engine.check_network_urls("https://example.com/a.js", "https://example.com/", "script")
        self.load_ms = (time.perf_counter() - t) * 1000
        self.load_how = how if self.engine else "none"

    def stale(self):
        try:
            age = time.time() - min(os.path.getmtime(_list_path(n)) for n in LISTS)
        except (OSError, ValueError):
            return True
        return age > REFRESH

    def refresh(self, force=False, wait=False):
        """Fetch the lists (when stale) and swap in a fresh engine, on a thread."""
        if not force and not self.stale():
            return
        def work():
            for name, url in LISTS.items():
                try:
                    _fetch(name, url)
                except Exception as err:
                    print(f"iris shield: {name} not refreshed: {err}", flush=True)
            fresh = _compile()
            if fresh:
                fresh.serialize_to_file(ENGINE)
                self.engine = fresh             # one assignment: never half-swapped
        th = threading.Thread(target=work, name="iris-lists", daemon=True)
        th.start()
        if wait:
            th.join()

    # ── the interceptor ─────────────────────────────────────────────────
    def interceptRequest(self, info):
        e = self.engine
        if e is None:
            return
        kind = KINDS.get(info.resourceType(), "other")
        if kind == "document":          # never block a page the user asked for
            return
        t = time.perf_counter_ns()
        r = e.check_network_urls(info.requestUrl().toString(),
                                 info.firstPartyUrl().toString(), kind)
        dt = time.perf_counter_ns() - t
        self.seen += 1
        self.spent_ns += dt
        if dt > self.worst_ns:
            self.worst_ns = dt
        if r.matched and not r.exception:
            self.blocked += 1
            info.block(True)

    def stats(self):
        n = max(1, self.seen)
        return {"engine": self.load_how, "loadMs": round(self.load_ms, 1),
                "seen": self.seen, "blocked": self.blocked,
                "meanUs": round(self.spent_ns / n / 1000, 1),
                "worstUs": round(self.worst_ns / 1000, 1)}
