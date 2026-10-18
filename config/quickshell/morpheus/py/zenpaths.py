# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# WHERE A BACKEND KEEPS THINGS, AND HOW IT WRITES THEM — the suite's Python
# side (clio, calypso). Stdlib only.
#
#   write_atomic(path, data)     whole or not at all: a .part beside it,
#                                synced, then renamed over (a crash mid-write
#                                leaves the old file, never half of one)
#   runtime_dir(app)             $XDG_RUNTIME_DIR/<app>, private (0700):
#                                sockets, locks
#   data_dir(app)                $XDG_DATA_HOME/<app> (~/.local/share)
#   cache_dir(app)               $XDG_CACHE_HOME/<app> (~/.cache)
#
# Each is made when asked for. Lifted out of clio (write_atomic) and calypso
# (runtime_dir) on 2026-10-18. Named zenpaths, not files
# (delphi/core has a files.py, which a morpheus/py/files.py shadowed) nor xdg
# (pyxdg's name): morpheus/py goes first on a backend's path, so a common
# name here hides the backend's own module or a library's.

import os


def write_atomic(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".part"
    with open(tmp, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode("utf-8"))
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def runtime_dir(app):
    base = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    d = os.path.join(base, app)
    os.makedirs(d, mode=0o700, exist_ok=True)
    os.chmod(d, 0o700)
    return d


def _xdg(var, fallback, app):
    d = os.path.join(os.environ.get(var) or os.path.expanduser(fallback), app)
    os.makedirs(d, exist_ok=True)
    return d


def data_dir(app):
    return _xdg("XDG_DATA_HOME", "~/.local/share", app)


def cache_dir(app):
    return _xdg("XDG_CACHE_HOME", "~/.cache", app)
