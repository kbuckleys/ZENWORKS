# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# ONE IRIS. A link clicked in another application runs `iris <url>` (the
# .desktop's Exec); with iris already up that must become a tab in it, not a
# second browser. The running iris listens on a local socket; a new `iris`
# knocks first and, answered, hands its request over and leaves — before Qt
# or Chromium is ever started, so it costs a few milliseconds.
#
#   $XDG_RUNTIME_DIR/quickshell/iris.sock
#   one JSON line per request: {"open": "<url or empty>", "cloak": false}
#
# A socket left by an iris that crashed answers nobody: the knock is refused,
# the file is cleared, and this iris becomes the one that listens.

import json, os, socket

from PySide6.QtCore import QObject, Signal
from PySide6.QtNetwork import QLocalServer

PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "quickshell", "iris.sock")


def knock(url, cloak=False):
    """Hand the request to a running iris. True when one took it."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect(PATH)
        s.sendall((json.dumps({"open": url or "", "cloak": bool(cloak)}) + "\n").encode())
        return s.recv(16).startswith(b"ok")
    except OSError:
        return False
    finally:
        s.close()


class Door(QObject):
    """The running iris' side: each request arrives as `asked`."""
    asked = Signal(str, bool)

    def __init__(self, parent=None):
        super().__init__(parent)
        os.makedirs(os.path.dirname(PATH), exist_ok=True)
        self._server = QLocalServer(self)
        self._server.setSocketOptions(QLocalServer.SocketOption.UserAccessOption)
        QLocalServer.removeServer(PATH)          # a dead iris' socket, refused above
        if not self._server.listen(PATH):
            # (a path past the socket limit of 108 bytes, for one)
            print("iris door: not listening on %s: %s" % (PATH, self._server.errorString()), flush=True)
        self._server.newConnection.connect(self._take)

    def _take(self):
        while self._server.hasPendingConnections():
            c = self._server.nextPendingConnection()
            c.readyRead.connect(lambda c=c: self._read(c))
            c.disconnected.connect(c.deleteLater)

    def _read(self, c):
        if not c.canReadLine():
            return
        try:
            req = json.loads(bytes(c.readLine()).decode())
        except ValueError:
            c.disconnectFromServer()
            return
        c.write(b"ok\n")
        c.flush()
        c.disconnectFromServer()
        self.asked.emit(str(req.get("open") or ""), bool(req.get("cloak")))

    def close(self):
        self._server.close()
        QLocalServer.removeServer(PATH)
