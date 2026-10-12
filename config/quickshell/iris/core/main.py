# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# IRIS' ENTRY — run by bin/iris (which settles the GL vendor first); the
# arguments are bin/iris' own, see there.

import os, sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

if sys.argv[1:2] == ["--lists"]:
    from shield import Shield
    from PySide6.QtCore import QCoreApplication
    app = QCoreApplication(sys.argv)
    s = Shield()
    s.refresh(force=True, wait=True)
    s._load()
    print(s.stats())
    sys.exit(0)

# ── ONE IRIS ────────────────────────────────────────────────────────────
# `iris [--cloak] [url]`: with an iris already up, the request is handed to
# it (door.py) and this one leaves — before Qt is even imported.
check = sys.argv[1:2] == ["--check"]
cloak = "--cloak" in sys.argv[1:]
args = [a for a in sys.argv[1:] if not a.startswith("--")]
url = args[0] if args else ""
if not check and not os.environ.get("IRIS_SELFTEST"):
    import door
    if door.knock(url, cloak):
        sys.exit(0)

from host import main
sys.exit(main([sys.argv[0]] + ([url] if url else []), check=check, cloak=cloak))
