# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE HOST — iris is its own process: PySide6 runs Qt Quick and Qt WebEngine,
# the window is QML. Not quickshell: quickshell builds its application with
# an empty argv, and WebEngine refuses to start without a program name.
# A process of its own also means closing iris gives every byte back, and a
# browser crash never reaches the shell.
#
# ORDER MATTERS, at both ends:
#   start   shared GL contexts + QtWebEngineQuick.initialize() BEFORE the
#           application exists, or WebEngine draws without the GPU; the
#           IrisHost singletons registered BEFORE the engine; the profiles
#           (Profiles.qml) made and shielded BEFORE the window that uses them
#   stop    the window (every view) goes first, the profiles after: a profile
#           released under a live page is Chromium's "expect troubles"

import os, sys

from PySide6.QtCore import QCoreApplication, QObject, QProcess, QStandardPaths, Qt, QUrl, Property, Slot, Signal
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QJSEngine, QQmlApplicationEngine, QQmlComponent, qmlRegisterSingletonInstance
from PySide6.QtWebEngineQuick import QtWebEngineQuick

from door import Door
from keep import History, Session
from shelllink import ShellLink
from shield import Shield
from toolkit import Toolkit
from zenonfeed import ZenonFeed

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))     # iris/
DATA = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
                    "quickshell", "iris")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                     "quickshell", "iris")


class Bridge(QObject):
    """What the QML sees as `Iris`: the profiles, the shield, the start page.
    The profiles are handed in after the engine exists (they are made in
    QML), but before the window is loaded — so to the window they are fixed.
    `asked` is another `iris <url>` handing its request to this one."""
    asked = Signal(str, bool)

    def __init__(self, shield, start, selftest, start_cloak=False):
        super().__init__()
        self._shield, self._start, self._selftest = shield, start, selftest
        self._start_cloak = start_cloak
        self._downloads = ""
        self._profile = self._cloak = None

    @Property(bool, constant=True)
    def startCloak(self): return self._start_cloak

    # where downloads go: xdg-user-dirs' Downloads (a self-test's own)
    @Property(str, constant=True)
    def downloadDir(self):
        return self._downloads or QStandardPaths.writableLocation(
            QStandardPaths.StandardLocation.DownloadLocation)

    @Property(QObject, constant=True)
    def profile(self): return self._profile

    @Property(QObject, constant=True)
    def cloak(self): return self._cloak

    @Property(str, constant=True)
    def startUrl(self): return self._start

    @Property(bool, constant=True)
    def selftest(self): return self._selftest

    @Slot(result="QVariantMap")
    def shieldStats(self): return self._shield.stats()

    # what a page shows (shield.py's cosmetic filtering)
    @Slot(str, result="QVariantMap")
    def cosmeticFor(self, url): return self._shield.cosmetic(url)

    @Slot(str, list, list, result=str)
    def genericFor(self, url, classes, ids): return self._shield.generic(url, classes, ids)

    @Slot(str)
    def report(self, line):
        print("iris:", line, flush=True)

    @Slot(QObject, float, float)
    def poke(self, window, x, y):
        """Self-test only: a right click at (x, y) in the window, delivered
        to iris' own window inside this process — never the desktop."""
        self.click(window, x, y, True)

    @Slot(QObject, float, float)
    def hover(self, window, x, y):
        """Self-test only: the pointer moved to (x, y) in iris' own window."""
        if not self._selftest:
            return
        from PySide6.QtCore import QEvent, QPointF
        from PySide6.QtGui import QMouseEvent
        p = QPointF(x, y)
        QCoreApplication.sendEvent(window, QMouseEvent(QEvent.Type.MouseMove, p, window.mapToGlobal(p),
                                                       Qt.MouseButton.NoButton, Qt.MouseButton.NoButton,
                                                       Qt.KeyboardModifier.NoModifier))

    @Slot(QObject, float, float, bool)
    def click(self, window, x, y, right):
        """Self-test only: a click at (x, y) in iris' own window."""
        if not self._selftest:
            return
        from PySide6.QtCore import QEvent, QPointF
        from PySide6.QtGui import QMouseEvent
        p = QPointF(x, y)
        b = Qt.MouseButton.RightButton if right else Qt.MouseButton.LeftButton
        for kind in (QEvent.Type.MouseButtonPress, QEvent.Type.MouseButtonRelease):
            buttons = b if kind == QEvent.Type.MouseButtonPress else Qt.MouseButton.NoButton
            QCoreApplication.sendEvent(window, QMouseEvent(kind, p, window.mapToGlobal(p), b,
                                                           buttons, Qt.KeyboardModifier.NoModifier))

    @Slot(result=float)
    def memoryMb(self):
        """Self-test: resident memory of iris and every process under it
        (Chromium's renderers, its GPU and utility processes), in MiB."""
        kids, rss = {}, 0
        for d in os.listdir("/proc"):
            if not d.isdigit():
                continue
            try:
                with open("/proc/%s/stat" % d) as f:
                    ppid = int(f.read().rsplit(")", 1)[1].split()[1])
                kids.setdefault(ppid, []).append(int(d))
            except (OSError, ValueError, IndexError):
                pass
        todo, seen = [os.getpid()], set()
        while todo:
            p = todo.pop()
            if p in seen:
                continue
            seen.add(p)
            todo += kids.get(p, [])
            try:
                with open("/proc/%d/status" % p) as f:
                    for line in f:
                        if line.startswith("VmRSS:"):
                            rss += int(line.split()[1])
            except OSError:
                pass
        return round(rss / 1024.0, 1)

    @Slot(QObject, float, float, float)
    def wheelAt(self, window, x, y, dy):
        """A precise wheel of `dy` px (down positive) at (x, y) in the window,
        through the window's own delivery — so Chromium scrolls whatever is
        there on its compositor thread, as for a touchpad. PageScroll's way of
        moving a page (the caller turns iris' own wheel overlay off around
        this call, or the event would come straight back to it)."""
        from PySide6.QtCore import QPoint, QPointF
        from PySide6.QtGui import QWheelEvent
        p = QPointF(x, y)
        d = QPoint(0, -round(dy))
        ev = QWheelEvent(p, window.mapToGlobal(p), d, d, Qt.MouseButton.NoButton,
                         Qt.KeyboardModifier.NoModifier, Qt.ScrollPhase.NoScrollPhase, False,
                         Qt.MouseEventSource.MouseEventSynthesizedByApplication)
        QCoreApplication.sendEvent(window, ev)

    @Slot(str, result=str)
    def env(self, name):
        """Self-test switches only (IRIS_*), never anything else."""
        return os.environ.get(name, "") if name.startswith("IRIS_") else ""

    @Slot(result=str)
    def scrollMode(self):
        return os.environ.get("IRIS_SCROLL", "wheel")

    @Slot(result=str)
    def shotPath(self):
        """Self-test only: where to save a picture of the window, if asked."""
        return os.environ.get("IRIS_SHOT", "") if self._selftest else ""

    @Slot(str, result=str)
    def pdfPath(self, title):
        """Where a page printed to PDF goes: the download directory, named
        for the page, never over a file already there."""
        base = "".join(c for c in (title or "page") if c not in '/\\:*?"<>|').strip()[:80] or "page"
        d = self.downloadDir
        os.makedirs(d, exist_ok=True)
        p, n = os.path.join(d, base + ".pdf"), 2
        while os.path.exists(p):
            p, n = os.path.join(d, "%s (%d).pdf" % (base, n)), n + 1
        return p

    @Slot(str)
    def openFile(self, path):
        """A file in the application the desktop opens it with."""
        if self._selftest:
            print("iris: would open", path, "(exists %s)" % os.path.exists(path), flush=True)
        else:
            QProcess.startDetached("gio", ["open", path])

    @Slot(str, str, str)
    def notify(self, title, message, origin):
        """A page's notification, as the desktop's own (howler keeps it)."""
        if self._selftest:
            print("iris: would notify", repr(title), repr(message), "from", origin, flush=True)
        else:
            QProcess.startDetached("notify-send", ["-a", "Iris", "-i", "web-browser",
                                                   title or origin, message])

    @Slot()
    def raiseWindow(self):
        """Bring the window forward for a link opened elsewhere. Wayland lets
        no window raise itself; hyprland is asked for this process' window."""
        if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            QProcess.startDetached("hyprctl", ["dispatch", "focuswindow", "pid:%d" % os.getpid()])


def make_profiles(engine, shield, data, cache):
    """Profiles.qml's two profiles, each with the shield on it."""
    comp = QQmlComponent(engine, QUrl.fromLocalFile(os.path.join(HERE, "Profiles.qml")))
    made = comp.createWithInitialProperties({"dataDir": data, "cacheDir": cache})
    if made is None:
        raise RuntimeError("Profiles.qml: " + comp.errorString())
    # THE ENGINE'S, for exactly as long as the engine: made from Python it is
    # JS-owned, and the collector may take it — the profiles with it, under
    # live pages. Parented, it goes when the engine does, after the window.
    QJSEngine.setObjectOwnership(made, QJSEngine.ObjectOwnership.CppOwnership)
    made.setParent(engine)
    normal, cloak = made.property("normal"), made.property("cloak")
    for p in (normal, cloak):
        p.setUrlRequestInterceptor(shield)
    return made, normal, cloak


# ── THE GPU, FOR VIDEO TOO ──────────────────────────────────────────────
# Everything else in a page is already on the GPU (chrome://gpu: compositing,
# raster, canvas, WebGL); video decoding is the one thing Qt leaves on the
# CPU. Two halves, both measured (2026-10-12, RTX 5060 Ti):
#
#   the features   hand decoding to VA-API. Chromium asks the driver what it
#                  decodes and falls back to software for the rest, or for
#                  all of it when there is no driver — safe on any machine.
#   GBM on NVIDIA  Qt refuses GBM on NVIDIA and draws through Vulkan instead,
#                  and without GBM it turns video decoding off outright
#                  (--disable-features=AcceleratedVideoDecoder). Forced on,
#                  H.264, VP9, AV1 and HEVC all decode on the GPU (HEVC did
#                  not play at all before), 0 dropped frames at 1080p30, WebGL
#                  still on the GPU; Skia draws with GL rather than Vulkan.
#                  Only when the machine is all NVIDIA — scripts/egl.sh has
#                  already decided that and said so in the environment — and
#                  NVIDIA's VA-API driver (libva-nvidia-driver) is installed:
#                  without it, forcing GBM would cost Vulkan for nothing.
#
# Added to what the user sets in QTWEBENGINE_CHROMIUM_FLAGS, never instead.
VIDEO_FEATURES = ["AcceleratedVideoDecodeLinuxGL", "AcceleratedVideoDecodeLinuxZeroCopyGL",
                  "VaapiVideoDecoder", "VaapiOnNvidiaGPUs", "VaapiIgnoreDriverChecks"]
NVIDIA_VAAPI = "/usr/lib/dri/nvidia_drv_video.so"


def gpu_setup():
    have = os.environ.get("QTWEBENGINE_CHROMIUM_FLAGS", "").split()
    if not any(f.startswith("--enable-features=") for f in have):
        have.append("--enable-features=" + ",".join(VIDEO_FEATURES))
    os.environ["QTWEBENGINE_CHROMIUM_FLAGS"] = " ".join(have)
    all_nvidia = "nvidia" in os.environ.get("__EGL_VENDOR_LIBRARY_FILENAMES", "")
    # a real display only: offscreen (tests) has no GBM device, and forced
    # there Chromium loses its GPU context outright
    shown = os.environ.get("QT_QPA_PLATFORM", "wayland") not in ("offscreen", "minimal")
    if all_nvidia and shown and os.path.exists(NVIDIA_VAAPI):
        os.environ.setdefault("QTWEBENGINE_FORCE_USE_GBM", "1")


def main(argv, check=False, cloak=False):
    """The browser; with check=True, compile every iris .qml and quit (preflight)."""
    selftest = os.environ.get("IRIS_SELFTEST", "")
    start = selftest or (argv[1] if len(argv) > 1 and not check else "about:blank")

    gpu_setup()
    # A page's file chooser (an upload's Browse…) through the desktop portal:
    # the user's is termfilechooser, so it is terminus' own picker, as for
    # every other application on this desktop. Iris' process only.
    os.environ.setdefault("QT_QPA_PLATFORMTHEME", "xdgdesktopportal")
    QCoreApplication.setAttribute(Qt.ApplicationAttribute.AA_ShareOpenGLContexts)
    QtWebEngineQuick.initialize()
    app = QGuiApplication(argv)
    app.setApplicationName("iris")
    app.setDesktopFileName("iris")          # Hyprland's class, the .desktop's id

    shield = Shield()
    bridge = Bridge(shield, start, bool(selftest), cloak)
    # a self-test keeps nothing of the user's: its cookies, history and
    # session go to a directory of its own, gone with it
    data, cache = DATA, CACHE
    if selftest:
        import tempfile
        data = cache = tempfile.mkdtemp(prefix="iris-selftest-")
    if selftest:
        bridge._downloads = os.path.join(data, "Downloads")
    history = History(os.path.join(data, "history.sqlite"))
    session = Session(os.path.join(data, "session.json"))
    # the toolkit's Zenon is the shell's base, fed the shell's inputs (zenonfeed.py)
    feed = ZenonFeed()
    # `import IrisHost` — singletons, not context properties: they live as
    # long as the engine, where a context is cleared before the window goes.
    # Registered BEFORE the engine exists; after, PySide confused QML's types.
    qmlRegisterSingletonInstance(Bridge, "IrisHost", 1, 0, "Iris", bridge)
    qmlRegisterSingletonInstance(ZenonFeed, "IrisHost", 1, 0, "ZenonFeed", feed)
    qmlRegisterSingletonInstance(History, "IrisHost", 1, 0, "History", history)
    qmlRegisterSingletonInstance(Session, "IrisHost", 1, 0, "Session", session)
    shell = ShellLink(active=not selftest)
    qmlRegisterSingletonInstance(ShellLink, "IrisHost", 1, 0, "Shell", shell)
    engine = QQmlApplicationEngine()
    toolkit = Toolkit()                     # morpheus, as iris may load it (toolkit.py)
    engine.addUrlInterceptor(toolkit)

    if check:
        return _check(engine)

    made, bridge._profile, bridge._cloak = make_profiles(engine, shield, data, cache)
    engine.load(QUrl.fromLocalFile(os.path.join(HERE, "Main.qml")))
    if not engine.rootObjects():
        return 1
    door = None
    if not selftest:
        shield.refresh()                    # stale lists only; after the window is up
        # the one iris: later `iris <url>`s arrive here (door.py). Never in a
        # self-test, which must not take the socket from the iris in use.
        door = Door()
        door.asked.connect(bridge.asked)

    code = app.exec()
    if door:
        door.close()
    shell.close()

    # the window and every view in it first, then the profiles, then the engine
    for root in engine.rootObjects():
        root.deleteLater()
    QCoreApplication.sendPostedEvents(None, 0)
    for p in (bridge._profile, bridge._cloak):
        p.setUrlRequestInterceptor(None)
    engine.deleteLater()                    # and Profiles.qml's object with it
    del engine
    QCoreApplication.sendPostedEvents(None, 0)
    history.close()
    if selftest:
        import shutil
        shutil.rmtree(data, ignore_errors=True)
    return code


def _check(engine):
    """Every .qml under iris/, compiled in this engine — with IrisHost and the
    toolkit's redirects in place, as at runtime. Nothing is instantiated.
    Prints in scripts/preflight.sh's format."""
    files = sorted(os.path.relpath(os.path.join(d, f), HERE)
                   for d, _, fs in os.walk(HERE) for f in fs if f.endswith(".qml"))
    files = [f for f in files if not f.startswith("shell" + os.sep)]   # the shell's, compiled by qs
    bad = 0
    for f in files:
        c = QQmlComponent(engine, QUrl.fromLocalFile(os.path.join(HERE, f)))
        while c.isLoading():
            QCoreApplication.processEvents()
        if c.isError():
            bad += 1
            print(f"PREFLIGHT FAIL iris/{f}: " + " ".join(e.toString() for e in c.errors()), flush=True)
    print(f"PREFLIGHT {len(files)} compiled in iris, {bad} failed", flush=True)
    return 1 if bad else 0
