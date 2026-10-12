# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE SHELL'S ZENON INPUTS, FOR IRIS. morpheus/ThemeSync writes them to
# $XDG_RUNTIME_DIR/quickshell/zenon.json whenever they change; this watches
# that file and hands it to iris/feed/Zenon.qml, which feeds ZenonBase — the same
# base the shell wears. No shell, no file: ZenonBase falls back to Zenon.
#
# The file is replaced atomically, which ends a watch on the old inode, so the
# path is watched again after every change.

import json, os

from PySide6.QtCore import QObject, QFileSystemWatcher, Property, Signal

PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "quickshell", "zenon.json")


class ZenonFeed(QObject):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._d = {}
        self._watch = QFileSystemWatcher(self)
        self._watch.fileChanged.connect(self._read)
        self._watch.directoryChanged.connect(self._read)     # the file appearing
        os.makedirs(os.path.dirname(PATH), exist_ok=True)
        self._watch.addPath(os.path.dirname(PATH))
        self._read()

    def _read(self, *_):
        if os.path.exists(PATH) and PATH not in self._watch.files():
            self._watch.addPath(PATH)
        try:
            with open(PATH, encoding="utf-8") as f:
                d = json.load(f)
        except (OSError, ValueError):
            return                  # missing or mid-write: keep what we wear
        if d != self._d:
            self._d = d
            self.changed.emit()

    def _get(self, k, default):
        v = self._d.get(k)
        return default if v is None else v

    cfg = Property("QVariantMap", lambda s: s._get("cfg", {}), notify=changed)
    fileTheme = Property("QVariantMap", lambda s: s._get("fileTheme", {}), notify=changed)
    followTheme = Property("QVariant", lambda s: s._d.get("followTheme"), notify=changed)
    daylight = Property(bool, lambda s: bool(s._get("daylight", True)), notify=changed)
    wallAccent = Property(str, lambda s: s._get("wallAccent", "transparent"), notify=changed)
