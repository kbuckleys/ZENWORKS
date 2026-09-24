#!/usr/bin/sh

# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# The portal's file chooser, answered by terminus instead of yazi in a terminal.
#
# xdg-desktop-portal-termfilechooser runs this and BLOCKS on it: whatever is in
# "$out" when this exits is what the asking application receives, and an empty
# file means the user cancelled.
#
# Two things this has to get right, both learned the hard way:
#
#   It must not hang when terminus is not there. The first version waited on the
#   marker file forever, so a shell that was restarting — or simply not running
#   — left Firefox waiting on a dialog that was never going to appear, with
#   nothing anywhere saying why.
#
#   It must say what happened. The portal's own log reports only "could not
#   execute ...: exit code 0", which is true and useless. This keeps its own.

multiple="$1"
directory="$2"
save="$3"
path="$4"
out="$5"
debug="$6"

log="${XDG_CACHE_HOME:-$HOME/.cache}/terminus/portal.log"
mkdir -p "$(dirname "$log")"
say() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$log"; }

# NOT `set -e`. Every failure here has a correct response that is not "die
# silently", and dying silently is what leaves the caller hanging.
if [ "$debug" = 1 ]; then
    set -x
fi

say "request multiple=$multiple directory=$directory save=$save path=$path"

: > "$out"
rm -f "$out.done"

# The ANSWER is checked, not just the exit status, and that distinction is not
# academic: a handler that throws half way through still exits 0 with empty
# output, which is how a save dialog once accepted every request and showed
# nothing while this script waited on a marker no one was going to write.
# "picking" is the only reply that means a dialog is up.
reply=$(qs ipc call Terminus pick "$multiple" "$directory" "$save" "$path" "$out" 2>>"$log")
if [ "$reply" != "picking" ]; then
    say "terminus did not open a picker (reply: '${reply:-none}'); cancelling"
    exit 0
fi

# No overall timeout: choosing a file takes as long as it takes, and cutting
# that short would hand the application a cancel nobody asked for. The guard is
# terminus itself — if the shell goes away mid-pick, stop waiting rather than
# holding the caller open forever.
#
# The check is "is MY DIALOG still up", not "is a terminus running". Those came
# apart the first time the shell was restarted mid-pick: the picker went with
# it, a fresh terminus answered `status` perfectly well, and this loop waited for
# a marker that nothing was ever going to write — holding the asking
# application's file dialog open forever, so the next attempt to open one
# appeared to do nothing at all. `picking=false` is a dialog that is gone.
# THE MARKER IS CHECKED BEFORE THE VERDICT, AND AGAIN AFTER IT.
#
# The answer is written asynchronously: terminus stops "picking" and the marker
# lands a few milliseconds later. This loop used to test the marker only in the
# `while` condition — so after the sleep it asked terminus for its status FIRST,
# saw picking=false, and cancelled a save that had just been confirmed. Both
# things become true in the same instant, and the status check was tested first,
# so it won almost every time: the portal log read 124 cancellations against 2
# successes, and every one of those handed the application response code 2 —
# not "the user cancelled" but "the dialog broke" — which is what made firefox
# fall back to downloading into its own last-used folder on its own.
#
# So: look for the marker immediately after waking, and look once more after a
# grace period before ever declaring a cancel.
while [ ! -e "$out.done" ]; do
    sleep 0.1
    [ -e "$out.done" ] && break
    if ! st=$(qs ipc call Terminus status 2>/dev/null); then
        say "terminus went away mid-pick; cancelling"
        exit 0
    fi
    case "$st" in
        *picking=false*)
            # A dialog that is gone has usually just answered. Give the write
            # time to land rather than racing it, and never delete the marker —
            # it is somebody else's in-flight answer.
            sleep 0.3
            [ -e "$out.done" ] && break
            say "picker closed without answering; cancelling"
            exit 0
            ;;
    esac
done

rm -f "$out.done"
say "answered with $(wc -l < "$out") path(s)"
