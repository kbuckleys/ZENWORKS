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

from host import main
sys.exit(main(sys.argv, check=sys.argv[1:2] == ["--check"]))
