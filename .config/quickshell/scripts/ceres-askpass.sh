#!/usr/bin/env bash
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# CERES ASKPASS — sudo's password, from ceres' own field.
#
# sudo -A runs whatever SUDO_ASKPASS names and reads the password from its
# stdout. Ceres names this, and hands the password over the fifo in
# CERES_FIFO: typed into ceres, written once into the pipe, read once here.
# It is never in argv, never in the environment, never on disk.
#
# ONE WRONG GUESS, NEVER THREE. While the password has not yet been accepted
# the wrapper marks the fifo `.once`, and this answers exactly one call: a
# wrong password makes sudo ask again, the second call finds `.spent` and
# declines, and sudo gives up after ONE failed attempt. Answering it again
# would hand sudo the same wrong password three times — three failures, and
# pam_faillock locks the account.
#
# Once sudo has accepted it, `.once` is gone and every call is answered: the
# second step of a transaction, paru's --sudoloop, an AUR build that outlasts
# sudo's cache — each gets the password it asks for, from the wrapper that
# is holding it for exactly as long as the transaction runs.

f="${CERES_FIFO:-}"
[ -n "$f" ] && [ -p "$f" ] || exit 1
if [ -e "$f.once" ]; then
  [ -e "$f.spent" ] && exit 1
  : > "$f.spent"
fi

# Under a timeout as a whole: `read -t` only starts counting once the fifo is
# OPEN, and opening a fifo blocks until something writes to it — so with no
# writer left (a wrapper that died) a bare read would wait forever.
pw=$(timeout 30 sh -c 'IFS= read -r l < "$1" && printf %s "$l"' _ "$f" 2>/dev/null)
[ -n "$pw" ] || exit 1
printf '%s\n' "$pw"
