#!/bin/sh
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# EVERYTHING THAT CAN BE CHECKED WITHOUT OPENING A WINDOW, in one go:
#
#   scripts/preflight.sh
#
#   1. the JS tests (oracle/test.js) — the pure halves, the colour budget,
#      the type-name clashes
#   2. the QML tests (oracle/qmltests) — clicks, drags, scrollbars
#   3. EVERY .qml compiled. The shell builds most windows lazily, so a file
#      that no longer compiles stays silent until the day it is opened —
#      plato was broken that way on 2026-10-08 and nothing said so.
#   4. what the running shell has warned about since it last reloaded —
#      runtime errors no compile can see
#
# The compile pass runs a throwaway quickshell config that only calls
# Qt.createComponent on each file: nothing is instantiated, no window opens,
# no setting is written. It needs the Wayland session (layer-shell types do
# not exist offscreen).

set -u
here=$(dirname "$(readlink -f "$0")")
root=$(dirname "$here")
fail=0

echo "── JS tests"
node "$root/oracle/test.js" 2>&1 | grep -vE '^  ok ' || true
node "$root/oracle/test.js" >/dev/null 2>&1 || fail=1

echo "── QML tests"
"$root/oracle/qmltests/run.sh" 2>&1 | grep -E 'Totals|FAIL' || fail=1

echo "── compiling every .qml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Singletons first: compiled after a file that already pulled one in as a
# singleton type, Qt intermittently refuses the file itself ("pragma Singleton
# used with a non composite singleton type", seen for howler/Howler.qml).
all=$(cd "$root" && find . -name '*.qml' -not -path './oracle/qmltests/*' -not -name 'shell.qml' \
       | sed 's#^\./##' | sort)
single=$(cd "$root" && printf '%s\n' $all | while read -r f; do grep -q '^pragma Singleton' "$f" && echo "$f"; done)
printf '%s\n' $single > "$tmp/singletons"
rest=$(printf '%s\n' $all | grep -vxF -f "$tmp/singletons")
list=$(printf '%s\n' $single $rest | sed '/^$/d; s/.*/"&"/' | paste -sd,)
cat > "$tmp/shell.qml" <<EOF
import QtQuick
import Quickshell
ShellRoot {
  property var files: [$list]
  property int i: 0
  property int bad: 0
  property var comp: null
  function next() {
    if (i >= files.length) { console.log("PREFLIGHT " + files.length + " compiled, " + bad + " failed"); Qt.quit(); return; }
    comp = Qt.createComponent("file://$root/" + files[i]);
    poll.start();
  }
  Timer { id: poll; interval: 10; repeat: true; onTriggered: {
    if (comp.status === Component.Loading) return;
    stop();
    if (comp.status === Component.Error) { bad++; console.log("PREFLIGHT FAIL " + files[i] + ": " + comp.errorString()); }
    i++; next();
  } }
  Component.onCompleted: next()
}
EOF
out=$(timeout 900 qs -p "$tmp/shell.qml" 2>&1 | grep 'PREFLIGHT' | sed 's/^.*PREFLIGHT/ /')
printf '%s\n' "$out"
printf '%s' "$out" | grep -q ' 0 failed' || fail=1

# 4. what the RUNNING shell has said since its last reload. Errors that only
#    happen while things run (a null at startup, a recycled delegate) never
#    reach a compile; they are only ever in this log, and only for windows
#    that were open. The known noise is left out.
echo "── the live shell's warnings since its last reload"
qs log 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' \
  | awk '/Reloading configuration/{buf=""} {buf=buf"\n"$0} END{print buf}' \
  | grep -E 'WARN|ERROR' \
  | grep -vE 'textinput|grabToImage|usedbeforedeclared|was built against Qt' \
  | sed 's/^/   /' | tail -15 || true

[ $fail -eq 0 ] && echo "── all clear" || echo "── SOMETHING FAILED (above)"
exit $fail
