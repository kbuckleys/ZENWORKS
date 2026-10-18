#!/bin/sh
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# WHAT THIS SHELL STANDS ON, in one line: the packages whose updates have
# broken it before (a Qt from [testing] ahead of the quickshell built for
# it; Hyprland's move to Lua). Printed comma-separated, the same way every
# time, so two runs compare as strings:
#
#   quickshell 0.3.2-1, qt6-base 6.12.0-3, qt6-declarative 6.12.0-1, ...
#
#   scripts/stack.sh          the line
#   scripts/stack.sh --stamp  also write it to the stamp: what the last
#                             clean preflight ran on (preflight does this)
#
# oracle/doctor.sh prints both, and Health says when they differ — "run
# preflight" after an update, before anything is found broken by hand.

pkgs="quickshell qt6-base qt6-declarative qt6-wayland qt6-multimedia hyprland jemalloc"
stamp="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/preflight-stamp"

if command -v pacman >/dev/null 2>&1; then
  line=$(pacman -Q $pkgs 2>/dev/null | paste -sd, | sed 's/,/, /g')
else
  # not Arch: what the tools themselves say
  line=$( { qs --version 2>/dev/null | head -1; hyprctl version 2>/dev/null | head -1; } | paste -sd, | sed 's/,/, /g')
fi

if [ "${1:-}" = "--stamp" ]; then
  mkdir -p "$(dirname "$stamp")"
  printf '%s\n' "$line" > "$stamp"
fi
printf '%s\n' "$line"
