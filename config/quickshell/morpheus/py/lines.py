# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# JSON LINES — the suite's backends, spoken to on stdin/stdout. Delphi's
# (git) and calypso's (passwords) are both this: a window's manager starts the
# daemon (terminus/LineDaemon.qml) and writes one request per line,
#
#   {"id": 7, "op": "status", "args": {...}, ...}
#
# and reads one line per message:
#
#   {"id": 7, "ok": true, "result": ...}            the answer, exactly once
#   {"id": 7, "ok": false, "error": "...", "kind": "cancelled"|...}
#   {"id": 7, "event": {...}}                       progress, before the answer
#   {"event": {...}}                                not tied to a request
#
# Each request runs on a thread of its own, so a slow one never holds up the
# next. {"op": "cancel", "args": {"id": 7}} stops request 7 and every process
# it started (Cancel). The first line out is {"event": {"ready": true,
# "protocol": N}}: the window refuses a daemon whose N is not its own, so a
# quickshell update and a backend change never fail silently into each other.
#
# Stdlib only. Lifted out of delphi/core/server.py (2026-10-11) when calypso
# wanted the same loop.

import json
import os
import signal
import sys
import threading

_out_lock = threading.Lock()
# where messages go: stdout, or the client of serve_socket (None: nobody,
# an answer for a client that has gone is dropped)
_sink = sys.stdout


def send(msg):
    line = json.dumps(msg, ensure_ascii=False, separators=(",", ":"))
    with _out_lock:
        if _sink is None:
            return
        try:
            _sink.write(line + "\n")
            _sink.flush()
        except (OSError, ValueError):
            pass   # the client went mid-answer


class Cancelled(Exception):
    pass


class Cancel:
    """A request's off switch. The worker running a request hands it to every
    process it starts; cancel() kills whichever one is running and makes every
    later start raise Cancelled instead."""

    def __init__(self):
        self.done = False
        self._procs = set()
        self._lock = threading.Lock()

    def attach(self, proc):
        with self._lock:
            if self.done:
                kill(proc)
                raise Cancelled()
            self._procs.add(proc)

    def detach(self, proc):
        with self._lock:
            self._procs.discard(proc)

    def cancel(self):
        with self._lock:
            self.done = True
            procs = list(self._procs)
        for p in procs:
            kill(p)

    def check(self):
        if self.done:
            raise Cancelled()


def kill(proc):
    """A process started with start_new_session=True, and all it started."""
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass


class Service:
    """The loop's other half. A daemon subclasses it and answers:

      dispatch(op, req, args, cancel, emit) → the result (JSON-able)
      failure(e) → the error message's fields for an exception it knows
                   ({"kind": …, "error": …}), or None for a bug
      special(req) → True when it answered a request itself, on this thread
                     (one that must not wait behind a thread's start)
      close()    → stop everything it started
    """

    def __init__(self):
        self.cancels = {}

    def handle(self, req):
        rid, op = req.get("id"), req.get("op", "")
        args = req.get("args") or {}
        if op == "cancel":
            c = self.cancels.get(args.get("id"))
            if c:
                c.cancel()
            return send({"id": rid, "ok": True, "result": {}})
        if self.special(req):
            return None
        cancel = Cancel()
        self.cancels[rid] = cancel
        threading.Thread(target=self._run, args=(rid, op, req, args, cancel),
                         daemon=True).start()
        return None

    def _run(self, rid, op, req, args, cancel):
        emit = lambda ev: send({"id": rid, "event": ev})
        try:
            res = self.dispatch(op, req, args, cancel, emit)
            send({"id": rid, "ok": True, "result": res})
        except Cancelled:
            send({"id": rid, "ok": False, "kind": "cancelled", "error": "cancelled"})
        except Exception as e:   # a bug here must not take the daemon down
            known = self.failure(e)
            if known is None:
                known = {"kind": "internal", "error": f"{type(e).__name__}: {e}"}
            send(dict({"id": rid, "ok": False}, **known))
        finally:
            self.cancels.pop(rid, None)

    def special(self, req):
        return False

    def failure(self, e):
        return None

    def close(self):
        for c in list(self.cancels.values()):
            c.cancel()


def serve(service, protocol, ready=None):
    """Read requests until stdin ends. Told to stop (SIGTERM: the window's
    manager going idle, or a kill), everything the service started stops with
    it — a child in a session of its own would otherwise outlive a plain exit."""
    def stop(sig, frame):
        service.close()
        os._exit(0)
    signal.signal(signal.SIGTERM, stop)
    send({"event": dict({"ready": True, "protocol": protocol, "pid": os.getpid()},
                        **(ready or {}))})
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
            except ValueError:
                send({"ok": False, "kind": "protocol", "error": "not JSON"})
                continue
            service.handle(req)
    finally:
        service.close()


# ── OR ON A SOCKET, OUTLIVING ITS WINDOW ──────────────────────────────────
# The same loop for a daemon that must not die with quickshell (calypso
# with auto-lock "Never": an unlocked vault stays unlocked across a shell
# restart). It listens on `path` (mode 0600, only this user's processes
# answered); its client is a bridge the window starts (calypso/bin/calypsod)
# relaying stdin/stdout, so LineDaemon never knows. ONE CLIENT: a new one
# takes over (an old shell still dying), answers for the old are dropped.
# When the client goes, linger() says whether to wait for the next one;
# otherwise everything stops, as serve() does at the end of stdin.
def serve_socket(service, protocol, path, linger, ready=None):
    import socket
    import struct
    global _sink

    def stop(sig, frame):
        service.close()
        try:
            os.unlink(path)
        except OSError:
            pass
        os._exit(0)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    try:
        os.unlink(path)
    except OSError:
        pass
    old = os.umask(0o177)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(path)
    os.umask(old)
    os.chmod(path, 0o600)
    sock.listen(2)
    state = {"conn": None}
    gate = threading.Lock()

    def reader(conn):
        global _sink
        try:
            for line in conn.makefile("r", encoding="utf-8"):
                line = line.strip()
                if not line:
                    continue
                try:
                    req = json.loads(line)
                except ValueError:
                    send({"ok": False, "kind": "protocol", "error": "not JSON"})
                    continue
                service.handle(req)
        except (OSError, ValueError):
            pass
        with gate:
            if state["conn"] is not conn:
                return            # replaced: the new client goes on
            state["conn"] = None
            with _out_lock:
                _sink = None
        try:
            conn.close()
        except OSError:
            pass
        if not linger():
            stop(None, None)

    with _out_lock:
        _sink = None
    while True:
        conn, _ = sock.accept()
        try:
            uid = struct.unpack("3i", conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))[1]
        except OSError:
            uid = -1
        if uid != os.getuid():
            conn.close()
            continue
        with gate:
            prev = state["conn"]
            state["conn"] = conn
            with _out_lock:
                _sink = conn.makefile("w", encoding="utf-8")
        if prev is not None:
            try:
                prev.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        send({"event": dict({"ready": True, "protocol": protocol, "pid": os.getpid()},
                            **(ready or {}))})
        threading.Thread(target=reader, args=(conn,), daemon=True).start()
