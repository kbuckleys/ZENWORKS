#!/bin/sh
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE PACKAGE, BROUGHT LEVEL WITH THIS MACHINE. ZENWORKS ships the same
# config as is running here, file for file, except what is about one
# person's machine: those stay the package's generic copies, and the files
# generated from a choice made here (the theme) are never shipped at all.
#
#     scripts/sync-package.sh [-n] [package dir]
#
# -n shows what would change and changes nothing. The package directory
# defaults to ~/Downloads/ZENWORKS. home/.zshrc and home/.p10k.zsh are
# copied when they differ; etc/pacman.conf is only reported if it differs
# (it is the package's own); install.sh is never touched.
#
# KEPT GENERIC (the package's copy wins):
#   hypr/lua/defaults.lua   oracle's Default Apps — renderDefaultsLua's stock
#   hypr/lua/monitors.lua   the catch-all rule only
#   hypr/lua/input.lua      hyprland's stock input
#   xdg-desktop-portal-termfilechooser/config   the @CONFIG@ placeholder
# NEVER SHIPPED (generated here by quickshell's ThemeSync):
#   hypr/lua/theme.lua, kitty/theme.conf — absent is Zenon.
#   quickshell/themes/custom-*.json (and the older wallpaper-*.json) — the
#   themes saved from Follow Background on this machine.

set -eu

dry=""
if [ "${1:-}" = "-n" ]; then dry="-n"; shift; fi
pkg="${1:-$HOME/Downloads/ZENWORKS}"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"

[ -d "$pkg/config" ] || { echo "no package at $pkg (expected $pkg/config)" >&2; exit 1; }

for d in fastfetch hypr kitty quickshell xdg-desktop-portal xdg-desktop-portal-termfilechooser; do
    [ -d "$cfg/$d" ] || { echo "skip $d: not in $cfg"; continue; }
    set --
    case $d in
        hypr) set -- --exclude=/lua/defaults.lua --exclude=/lua/monitors.lua \
                     --exclude=/lua/input.lua --exclude=/lua/theme.lua ;;
        kitty) set -- --exclude=/theme.conf ;;
        xdg-desktop-portal-termfilechooser) set -- --exclude=/config ;;
        # themes saved here (Follow Background's Save) are this machine's
        quickshell) set -- --exclude=/themes/custom-*.json --exclude=/themes/wallpaper-*.json ;;
    esac
    mkdir -p "$pkg/config/$d"
    if [ -n "$dry" ]; then
        changes=$(rsync -ain --delete "$@" "$cfg/$d/" "$pkg/config/$d/" | grep -v '^\.d\.\.t' || true)
        printf '== %s: %s\n' "$d" "$(printf '%s' "$changes" | grep -c . || true)"
        printf '%s\n' "$changes" | grep -E '^\*deleting|^>f\+|^cd\+' | sed 's/^/   /' || true
    else
        rsync -a --delete "$@" "$cfg/$d/" "$pkg/config/$d/"
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
# pacman.conf is the package's own (testing repos and all): reported, never copied
cmp -s /etc/pacman.conf "$pkg/etc/pacman.conf" 2>/dev/null \
    || echo "note: etc/pacman.conf differs from /etc/pacman.conf (left as it is)"

[ -n "$dry" ] && exit 0

# a generated theme file in the package would pin every install to one theme
rm -f "$pkg/config/hypr/lua/theme.lua" "$pkg/config/kitty/theme.conf" \
      "$pkg"/config/quickshell/themes/custom-*.json "$pkg"/config/quickshell/themes/wallpaper-*.json

echo "-- left different (expected: the generic and generated files only):"
for d in fastfetch hypr kitty quickshell xdg-desktop-portal xdg-desktop-portal-termfilechooser; do
    [ -d "$cfg/$d" ] && diff -rq "$cfg/$d" "$pkg/config/$d" || true
done
