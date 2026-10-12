# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE SUITE'S TOOLKIT, LOADED IN IRIS. Iris imports morpheus' own files — not
# copies — but Qt compiles every singleton a directory's qmldir declares as
# soon as anything imports that directory, and morpheus' singletons are the
# SHELL's state (Jobs, Volume, Paths, Sysmon…): they import quickshell, which
# this process does not have, and iris has no business running a second copy
# of any of them. So when iris' engine asks for morpheus/qmldir it is handed
# a filtered one, made at launch from the real file:
#
#   Zenon       → iris/feed/Zenon.qml: the same ZenonBase, fed the shell's inputs
#   any other singleton → left out (what iris needs of the shell's state, it
#                 asks the shell for)
#   every type  → the real file, by an absolute file:// URL (Qt resolved a
#                 relative "../.." in a qmldir one level off)
#
# Types are compiled only when used, so a type that needs quickshell costs
# nothing until iris reaches for it — and then fails loudly, which is the cue
# to split it (as ZenonBase was split out of Zenon).

import os

from PySide6.QtCore import QUrl
from PySide6.QtQml import QQmlAbstractUrlInterceptor

SUITE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
IRIS = os.path.join(SUITE, "iris")
RUN = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                   "quickshell", "iris", "qmldir")


def filtered_qmldir(name):
    """Write iris' view of <suite>/<name>/qmldir; return its path."""
    src_dir = os.path.join(SUITE, name)
    out_dir = os.path.join(RUN, name)
    os.makedirs(out_dir, exist_ok=True)
    lines = []
    with open(os.path.join(src_dir, "qmldir"), encoding="utf-8") as f:
        for raw in f:
            p = raw.split()
            if len(p) >= 3 and p[-1].endswith((".qml", ".js")):
                single = p[0] == "singleton"
                type_name, file = p[1 if single else 0], p[-1]
                if name == "morpheus" and type_name == "Zenon":
                    target = QUrl.fromLocalFile(os.path.join(IRIS, "feed", "Zenon.qml")).toString()
                elif single:
                    continue
                else:
                    target = QUrl.fromLocalFile(os.path.join(src_dir, file)).toString()
                lines.append(" ".join(p[:-1] + [target]))
            elif p and p[0] == "module":
                lines.append(raw.rstrip("\n"))
    out = os.path.join(out_dir, "qmldir")
    with open(out + ".part", "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(out + ".part", out)
    return out


class Toolkit(QQmlAbstractUrlInterceptor):
    def __init__(self, names=("morpheus",)):
        super().__init__()
        self._map = {os.path.join(SUITE, n, "qmldir"): QUrl.fromLocalFile(filtered_qmldir(n))
                     for n in names}

    def intercept(self, url, kind):
        if url.isLocalFile():
            to = self._map.get(os.path.normpath(url.toLocalFile()))
            if to is not None:
                return to
        return url
