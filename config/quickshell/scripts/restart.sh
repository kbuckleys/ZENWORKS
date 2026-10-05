#!/bin/sh
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE ONE WAY THIS SHELL IS RESTARTED — oracle's Restart and icarus' both
# come through here, then through launch.sh like every other start.
#
# NOT `qs kill`. That asks the shell to exit cleanly, and quickshell's own
# teardown crashes on this config — in the dbusmenu / wayland teardown, after
# every line of QML has already stopped — so every restart ended in the crash
# handler: a dialog, a stale crash folder, and the crashed process re-exec'd by
# the handler before the relaunch could run (so `-n` declined it, and the
# "restarted" shell was the crash recovery). Eighteen of them in the crash
# folder before this script existed.
#
# A restart does not need a clean exit: the next instance rebuilds everything
# from disk. So the instance is ended with SIGTERM, which quickshell does not
# catch (only the crash signals are), and nothing of it runs on the way out.
# Settings are written as they change, not on exit, so nothing is lost.
#
# The pid comes from `qs list`, which knows which instance is THIS config's —
# a bare pkill would take any other quickshell config down with it.

dir=$(dirname "$(readlink -f "$0")")

pids=$(qs list -j 2>/dev/null | sed -n 's/.*"pid": *\([0-9]*\).*/\1/p')
for p in $pids; do kill -TERM "$p" 2>/dev/null; done

# gone within two seconds, or it is taken
for p in $pids; do
    n=0
    while kill -0 "$p" 2>/dev/null && [ $n -lt 20 ]; do sleep 0.1; n=$((n + 1)); done
    kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null
done

exec "$dir/launch.sh" -n -d "$@"
