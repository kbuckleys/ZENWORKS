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

from PySide6.QtCore import QCoreApplication, QObject, Qt, QUrl, Property, Slot, Signal
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QJSEngine, QQmlApplicationEngine, QQmlComponent, qmlRegisterSingletonInstance
from PySide6.QtWebEngineQuick import QtWebEngineQuick

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
    QML), but before the window is loaded — so to the window they are fixed."""

    def __init__(self, shield, start, selftest):
        super().__init__()
        self._shield, self._start, self._selftest = shield, start, selftest
        self._profile = self._cloak = None

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

    @Slot(str)
    def report(self, line):
        print("iris:", line, flush=True)


def make_profiles(engine, shield):
    """Profiles.qml's two profiles, each with the shield on it."""
    comp = QQmlComponent(engine, QUrl.fromLocalFile(os.path.join(HERE, "Profiles.qml")))
    made = comp.createWithInitialProperties({"dataDir": DATA, "cacheDir": CACHE})
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


def main(argv, check=False):
    """The browser; with check=True, compile every iris .qml and quit (preflight)."""
    selftest = os.environ.get("IRIS_SELFTEST", "")
    start = selftest or (argv[1] if len(argv) > 1 and not check else "about:blank")

    QCoreApplication.setAttribute(Qt.ApplicationAttribute.AA_ShareOpenGLContexts)
    QtWebEngineQuick.initialize()
    app = QGuiApplication(argv)
    app.setApplicationName("iris")
    app.setDesktopFileName("iris")          # Hyprland's class, the .desktop's id

    shield = Shield()
    bridge = Bridge(shield, start, bool(selftest))
    # the toolkit's Zenon is the shell's base, fed the shell's inputs (zenonfeed.py)
    feed = ZenonFeed()
    # `import IrisHost` — singletons, not context properties: they live as
    # long as the engine, where a context is cleared before the window goes.
    # Registered BEFORE the engine exists; after, PySide confused QML's types.
    qmlRegisterSingletonInstance(Bridge, "IrisHost", 1, 0, "Iris", bridge)
    qmlRegisterSingletonInstance(ZenonFeed, "IrisHost", 1, 0, "ZenonFeed", feed)
    engine = QQmlApplicationEngine()
    toolkit = Toolkit()                     # morpheus, as iris may load it (toolkit.py)
    engine.addUrlInterceptor(toolkit)

    if check:
        return _check(engine)

    made, bridge._profile, bridge._cloak = make_profiles(engine, shield)
    engine.load(QUrl.fromLocalFile(os.path.join(HERE, "Main.qml")))
    if not engine.rootObjects():
        return 1
    if not selftest:
        shield.refresh()                    # stale lists only; after the window is up

    code = app.exec()

    # the window and every view in it first, then the profiles, then the engine
    for root in engine.rootObjects():
        root.deleteLater()
    QCoreApplication.sendPostedEvents(None, 0)
    for p in (bridge._profile, bridge._cloak):
        p.setUrlRequestInterceptor(None)
    engine.deleteLater()                    # and Profiles.qml's object with it
    del engine
    QCoreApplication.sendPostedEvents(None, 0)
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
