# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# HANDING A SECRET OVER — onto the clipboard, or typed where the cursor is.
# The daemon does both itself, so a password goes from the vault's CLI to
# wl-copy or wtype without ever reaching the window: the window says "copy
# item 7's password", never sees it.
#
# Always through stdin, never argv: argv is readable in /proc by anything
# running as you, and a secret starting with "-" would be taken for an option.

import shutil
import subprocess
import threading
import time

CLEAR_AFTER = 30


def _sensitive():
    """wl-clipboard 2.2.2+ marks an offer sensitive, and `wl-paste --watch
    cliphist store` then skips it — the secret never reaches the history."""
    try:
        r = subprocess.run(["wl-copy", "--help"], stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, timeout=5)
        return "--sensitive" in r.stdout
    except (OSError, subprocess.TimeoutExpired):
        return False


_SENSITIVE = None
_clear_lock = threading.Lock()
_clear_gen = [0]


def copy(secret, clear_after=CLEAR_AFTER):
    """On the clipboard, out of cliphist, and off the clipboard again after
    `clear_after` seconds if it is still there."""
    global _SENSITIVE
    from base import needs
    needs({"wl-copy": "wl-clipboard", "wl-paste": "wl-clipboard"}, "Copying")
    if _SENSITIVE is None:
        _SENSITIVE = _sensitive()
    argv = ["wl-copy"] + (["--sensitive"] if _SENSITIVE else [])
    # wl-copy forks a server that keeps the offer alive; its output closed so
    # this call returns as the copy lands
    r = subprocess.run(argv, input=secret.encode(), stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=10)
    if r.returncode != 0:
        raise RuntimeError("wl-copy failed")
    if not _SENSITIVE and shutil.which("cliphist"):
        # an older wl-clipboard: taken back out of the history once stored,
        # and only if the newest entry is this secret
        def scrub():
            time.sleep(0.5)
            try:
                top = subprocess.run(["cliphist", "list"], stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, timeout=5).stdout.split(b"\n")[0]
                if top and subprocess.run(["cliphist", "decode"], input=top + b"\n",
                                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                          timeout=5).stdout == secret.encode():
                    subprocess.run(["cliphist", "delete"], input=top + b"\n",
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                pass
        threading.Thread(target=scrub, daemon=True).start()
    with _clear_lock:
        _clear_gen[0] += 1
        gen = _clear_gen[0]

    def clear():
        time.sleep(clear_after)
        with _clear_lock:
            if gen != _clear_gen[0]:
                return           # something newer was copied since
        try:
            now = subprocess.run(["wl-paste", "-n"], stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, timeout=5).stdout
            if now == secret.encode():
                subprocess.run(["wl-copy", "--clear"], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            pass
    if clear_after > 0:
        threading.Thread(target=clear, daemon=True).start()
    return {"clearsIn": clear_after}


def type_(parts, delay=0.3):
    """`parts`: strings typed in order; "\\t" alone is the Tab key, "\\n"
    alone Return. Waits `delay` first — the popup that asked has to close and
    hand the keyboard back to the window the text is for."""
    from base import needs
    needs({"wtype": "wtype"}, "Typing it in")
    time.sleep(delay)
    for p in parts:
        if p == "\t":
            argv, data = ["wtype", "-k", "Tab"], None
        elif p == "\n":
            argv, data = ["wtype", "-k", "Return"], None
        else:
            argv, data = ["wtype", "-"], p.encode()
        r = subprocess.run(argv, input=data, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=30)
        if r.returncode != 0:
            raise RuntimeError("wtype failed")
    return {}
