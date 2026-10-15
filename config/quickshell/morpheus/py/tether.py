# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# popen(argv, **kw) — subprocess.Popen through scripts/tether, so a watcher
# a backend starts dies with the backend however the backend dies (a window's
# manager SIGKILLing it on a shell exit left delphi's three inotifywaits per
# repository running under init).
#
# Not a plain Popen([tether] + argv): the parent-death signal belongs to the
# THREAD that forked, and lines.Service runs each request on a thread that
# ends with the answer — a watch started there would be killed the moment
# it was armed. So every fork here happens on one thread kept for the life
# of the process, and the caller waits for its Popen.

import os
import queue
import shutil
import subprocess
import threading

TETHER = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.realpath(__file__)))), "scripts", "tether")

_jobs = queue.Queue()
_start = threading.Lock()
_thread = None


def _run():
    while True:
        argv, kw, box, done = _jobs.get()
        try:
            box.append(subprocess.Popen([TETHER] + list(argv), **kw))
        except BaseException as e:
            box.append(e)
        done.set()


def popen(argv, **kw):
    """Popen(argv, **kw), tethered. Raises FileNotFoundError when argv[0] is
    not installed, as Popen would (tether exits 127 then, so this checks
    first)."""
    global _thread
    if not os.path.isabs(argv[0]) and not shutil.which(argv[0]):
        raise FileNotFoundError(argv[0])
    with _start:
        if _thread is None:
            _thread = threading.Thread(target=_run, name="tether", daemon=True)
            _thread.start()
    box, done = [], threading.Event()
    _jobs.put((argv, kw, box, done))
    done.wait()
    if isinstance(box[0], BaseException):
        raise box[0]
    return box[0]

