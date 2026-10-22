#!/bin/sh
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE PACKAGE, BROUGHT LEVEL WITH THIS MACHINE. ZENWORKS ships the same
# config as is running here, file for file, except what is about one
# person's machine: those stay the package's generic copies, and the files
# generated from a choice made here (the theme, the fonts) are never
# shipped at all.
#
#     scripts/sync-package.sh [-n] [package dir]
#
# -n shows every file that would change and changes nothing. The package
# directory# defaults to ~/Projects/ZENWORKS (until 2026-10-11, ~/Downloads/ZENWORKS).
# home/.zshrc, home/.p10k.zsh and etc/pacman.conf are copied when they
# differ — pacman.conf too since 2026-10-11 (the user turned the testing
# repos off and expected the package to follow; before, it was the
# package's own and only reported). The installer and uninstaller
# (install, uninstall), README, LICENSE and .git are never touched.
#
# Which files those are is scripts/userfiles.txt, the one list update.sh
# and the package's uninstall read too:
#   generic    the package's copy wins: oracle's Default apps
#              (renderDefaultsLua's stock), the catch-all monitor rule,
#              hyprland's stock input, no shortcuts moved, Wake by mouse,
#              and the file chooser's @CONFIG@ placeholder
#   generated  never shipped (ThemeSync's theme.lua, font.lua,
#              hyprtoolkit.conf, kitty's theme.conf and font.conf — absent is
#              the default, and the shell writes them as it starts)
#   saved      never shipped (themes saved from Follow Background here)
#   seed       shipped from here (Plato's plugin list and their settings),
#              but never laid over a user's own by update.sh
# One line is shipped as the default rather than as it is here: base.lua's
# `rounding = N`, which oracle's Corner rounding rewrites in place.
#
# After a sync the package is checked: nothing generated or saved in it,
# every generic file present, the @CONFIG@ placeholder intact, no Python
# caches, no link pointing outside it. A problem stops with exit 3.

set -eu

dry=""
if [ "${1:-}" = "-n" ]; then dry="-n"; shift; fi
pkg="${1:-$HOME/Projects/ZENWORKS}"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
dirs="fastfetch hypr kitty quickshell xdg-desktop-portal xdg-desktop-portal-termfilechooser"

[ -d "$pkg/config" ] || { echo "no package at $pkg (expected $pkg/config)" >&2; exit 1; }

list="$(dirname -- "$0")/userfiles.txt"
[ -f "$list" ] || { echo "no $list" >&2; exit 1; }
# userfiles.txt's paths: every kind, or only the ones named ($1, a regex)
userfiles() { sed 's/#.*//' "$list" | awk -v k="${1:-.*}" 'NF == 2 && $1 ~ "^(" k ")$" { print $2 }'; }

# Oracle's Corner rounding default, and base.lua with it in place of this
# machine's (the line under the comment that names it)
corner="$(sed -n 's/^ *property int cornerRadius: *\([0-9][0-9]*\).*/\1/p' "$cfg/quickshell/oracle/Oracle.qml" | head -n1)"
[ -n "$corner" ] || { echo "no cornerRadius default in oracle/Oracle.qml" >&2; exit 1; }
stock_base() {
    awk -v n="$corner" '
        /oracle.s Corner rounding writes this number/ { mark = 1 }
        mark && /^[ \t]*rounding = [0-9]+,/ { sub(/[0-9]+/, n); mark = 0 }
        { print }' "$1"
}

# no globbing from here: the excludes carry their * to rsync as they are
set -f
for d in $dirs; do
    [ -d "$cfg/$d" ] || { echo "skip $d: not in $cfg"; continue; }
    # Python's caches (running delphi's backend here makes them) never ship
    set -- --exclude=__pycache__ --exclude=*.pyc
    for p in $(userfiles 'generic|generated|saved' | sed -n "s|^$d/|/|p"); do set -- "$@" "--exclude=$p"; done
    if [ "$d" = hypr ]; then set -- "$@" --exclude=/lua/base.lua; fi
    mkdir -p "$pkg/config/$d"
    if [ -n "$dry" ]; then
        changes=$(rsync -ain --delete "$@" "$cfg/$d/" "$pkg/config/$d/" | grep -v '^\.d\.\.t' || true)
        if [ "$d" = hypr ] && ! stock_base "$cfg/hypr/lua/base.lua" | cmp -s - "$pkg/config/hypr/lua/base.lua"; then
            changes="$(printf '%s\n%s' "$changes" ">f.c...... lua/base.lua (rounding shipped as $corner)" | grep . || true)"
        fi
        printf '== %s: %s\n' "$d" "$(printf '%s' "$changes" | grep -c . || true)"
        [ -n "$changes" ] && printf '%s\n' "$changes" | sed 's/^/   /'
    else
        rsync -a --delete "$@" "$cfg/$d/" "$pkg/config/$d/"
        if [ "$d" = hypr ]; then
            stock_base "$cfg/hypr/lua/base.lua" > "$pkg/config/hypr/lua/base.lua.part"
            mv -f "$pkg/config/hypr/lua/base.lua.part" "$pkg/config/hypr/lua/base.lua"
        fi
    fi
done

# the shell dotfiles ship as they are here, file for file
for f in .zshrc .p10k.zsh; do
    [ -f "$HOME/$f" ] || continue
    if ! cmp -s "$HOME/$f" "$pkg/home/$f" 2>/dev/null; then
        if [ -n "$dry" ]; then echo "== home: $f differs"
        else mkdir -p "$pkg/home"; cp -p "$HOME/$f" "$pkg/home/$f"; echo "home: $f updated"; fi
    fi
done
# pacman.conf ships as it is here — the repositories this machine uses
# (testing on or off) are the ones an install gets
if [ -f /etc/pacman.conf ] && ! cmp -s /etc/pacman.conf "$pkg/etc/pacman.conf" 2>/dev/null; then
    if [ -n "$dry" ]; then echo "== etc: pacman.conf differs"
    else mkdir -p "$pkg/etc"; cp /etc/pacman.conf "$pkg/etc/pacman.conf"; echo "etc: pacman.conf updated"; fi
fi

if [ -n "$dry" ]; then
    for p in $(userfiles 'generated|saved'); do
        set +f; for f in "$pkg"/config/$p; do [ -e "$f" ] && echo "== would remove from the package: ${f#"$pkg/"}"; done; set -f
    done
    exit 0
fi

# a generated file in the package would pin every install to this
# machine's theme or font, and a saved one is this machine's
for p in $(userfiles 'generated|saved'); do set +f; rm -f "$pkg"/config/$p; set -f; done

# ── the package, checked ──
bad=0
problem() { echo "!! $*" >&2; bad=1; }
for p in $(userfiles 'generated|saved'); do
    set +f; for f in "$pkg"/config/$p; do [ -e "$f" ] && problem "shipped though it is this machine's: ${f#"$pkg/"}"; done; set -f
done
for p in $(userfiles generic); do
    [ -f "$pkg/config/$p" ] || problem "the generic copy is missing: config/$p (add the stock one: what Oracle writes at its defaults)"
done
grep -q '@CONFIG@' "$pkg/config/xdg-desktop-portal-termfilechooser/config" 2>/dev/null \
    || problem "config/xdg-desktop-portal-termfilechooser/config lost its @CONFIG@ placeholder"
find "$pkg/config" "$pkg/home" \( -name __pycache__ -o -name '*.pyc' \) | grep -q . \
    && problem "Python caches in the package"
find "$pkg/config" "$pkg/home" -type l | while read -r l; do
    case "$(readlink "$l")" in /*) echo "!! a link pointing outside the package: ${l#"$pkg/"}" ;; esac
    [ -e "$l" ] || echo "!! a broken link: ${l#"$pkg/"}"
done | grep . >&2 && bad=1
[ "$bad" = 0 ] || { echo "the package needs looking at before it is pushed" >&2; exit 3; }

echo "-- left different (expected: the generic and generated files, and base.lua's rounding):"
for d in $dirs; do
    [ -d "$cfg/$d" ] && diff -rq -x __pycache__ "$cfg/$d" "$pkg/config/$d" || true
done
echo "-- the package checks out"
