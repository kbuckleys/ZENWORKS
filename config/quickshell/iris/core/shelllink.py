# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE LINE TO THE SHELL — one local socket, open while iris runs, to
# iris/shell/IrisManager.qml (a quickshell SocketServer). JSON a line at a
# time: iris' downloads go out as jobs for the shell's Jobs drawer, and the
# drawer's cancel comes back. See IrisManager for the messages.
#
# The shell is iris' core dependency but not its lifeline: restarted, or not
# up yet, the line is tried again every few seconds, and what is said while
# it is down is simply not heard — a download still lands in its directory.

import json, os

from PySide6.QtCore import QObject, QTimer, Signal, Slot
from PySide6.QtNetwork import QLocalSocket

PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "quickshell", "iris-shell.sock")


class ShellLink(QObject):
    cancelAsked = Signal(int)

    def __init__(self, active=True, parent=None):
        super().__init__(parent)
        self._sock = QLocalSocket(self)
        self._sock.readyRead.connect(self._read)
        self._retry = QTimer(self, interval=3000, singleShot=True)
        self._retry.timeout.connect(self._connect)
        self._sock.disconnected.connect(self._retry.start)
        self._sock.errorOccurred.connect(lambda *_: self._retry.start())
        # a self-test says nothing to the shell (its jobs are not the user's)
        if active:
            self._connect()

    def _connect(self):
        if self._sock.state() == QLocalSocket.LocalSocketState.UnconnectedState:
            self._sock.connectToServer(PATH)

    def _read(self):
        while self._sock.canReadLine():
            try:
                m = json.loads(bytes(self._sock.readLine()).decode())
            except ValueError:
                continue
            if isinstance(m, dict) and "cancel" in m:
                self.cancelAsked.emit(int(m["cancel"]))

    @Slot("QVariantMap")
    def send(self, message):
        if self._sock.state() == QLocalSocket.LocalSocketState.ConnectedState:
            self._sock.write((json.dumps(message) + "\n").encode())
            self._sock.flush()

    def close(self):
        self._retry.stop()
        self._sock.disconnectFromServer()
