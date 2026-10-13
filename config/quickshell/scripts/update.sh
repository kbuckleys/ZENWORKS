#!/bin/bash
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# ZENWORKS, BROUGHT UP TO DATE — for everyone who runs the suite without
# keeping it: the published repository cloned (shallow) into a scratch
# directory, its configs laid over this machine's, the scratch directory
# gone again. Nothing is left behind: no clone, no backup, no log.
#
#     scripts/update.sh [-n] [--force]
#
#   -n        say what would change, change nothing
#   --force   run even where the package is maintained (see below)
#
# What is YOURS is never touched — the same files sync-package.sh keeps out
# of the package: your default apps, monitors and input (hypr/lua/defaults,
# monitors, input), the theme files made from your theme (hypr/lua/theme.lua,
# kitty/theme.conf), themes saved from Follow Background, and the file
# chooser's config. Dotfiles (~/.zshrc, ~/.p10k.zsh) are left alone too:
# they are often edited by hand. Everything else in the suite's config
# directories is made exactly the published one.
#
# NOT ON THE MAINTAINER'S MACHINE: there the live config is AHEAD of what is
# published, and this would roll it back. A machine with the package
# checkout (~/Projects/ZENWORKS, sync-package.sh's) refuses without --force.
#
# Packages the new version needs and this machine lacks are listed at the
# end, for ceres (or paru) to install; this installs none itself.
#
# The repository: $ZENWORKS_REPO, else the published one. Run by oracle's
# Update (as a job in the shell's drawer), or by hand.

set -euo pipefail

REPO="${ZENWORKS_REPO:-https://github.com/kbuckleys/ZENWORKS}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
CONFIGS=(fastfetch hypr kitty quickshell xdg-desktop-portal xdg-desktop-portal-termfilechooser)

dry=""
force=""
for a in "$@"; do
  case "$a" in
    -n) dry=1 ;;
    --force) force=1 ;;
    *) echo "update: unknown argument $a" >&2; exit 2 ;;
  esac
done

if [[ -z "$force" && -d "$HOME/Projects/ZENWORKS/config" ]]; then
  echo "update: this machine maintains ZENWORKS (~/Projects/ZENWORKS) — its config is ahead of the published one; --force to roll it back anyway" >&2
  exit 3
fi

for tool in git rsync; do
  command -v "$tool" >/dev/null || { echo "update: $tool is needed" >&2; exit 4; }
done

# the scratch directory, and the promise that it goes whatever happens
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zenworks-update.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT INT TERM

echo "update: fetching $REPO"
git clone --quiet --depth 1 -- "$REPO" "$tmp/zenworks"
rev="$(git -C "$tmp/zenworks" log -1 --format='%h %cs %s' 2>/dev/null || true)"
echo "update: published version: ${rev:-unknown}"

changed=0
n=0
for d in "${CONFIGS[@]}"; do
  n=$((n + 1))
  src="$tmp/zenworks/config/$d"
  [[ -d "$src" ]] || continue
  ex=(--exclude=__pycache__ --exclude='*.pyc')
  case $d in
    hypr) ex+=(--exclude=/lua/defaults.lua --exclude=/lua/monitors.lua
               --exclude=/lua/input.lua --exclude=/lua/theme.lua) ;;
    kitty) ex+=(--exclude=/theme.conf) ;;
    xdg-desktop-portal-termfilechooser) ex+=(--exclude=/config) ;;
    quickshell) ex+=(--exclude='/themes/custom-*.json' --exclude='/themes/wallpaper-*.json') ;;
  esac
  mkdir -p -- "$CONFIG/$d"
  count=$(rsync -ai --delete ${dry:+-n} "${ex[@]}" "$src/" "$CONFIG/$d/" | grep -cv '^\.d\.\.t' || true)
  changed=$((changed + count))
  echo "update: ($n/${#CONFIGS[@]}) $d — $count change(s)"
  # run as a job (no terminal): how far along, as the drawer reads it
  [[ -t 1 ]] || printf '\r%d%%\r' $((n * 100 / ${#CONFIGS[@]}))
done

if [[ -z "$dry" ]]; then
  # a repository uploaded through GitHub's web page loses its executable
  # bits: the scripts and the launchers, set again (as the installer does)
  find "$CONFIG/quickshell" "$CONFIG/hypr" "$CONFIG/xdg-desktop-portal-termfilechooser" \
    -type f \( -name '*.sh' -o -name '*.py' -o -path '*/bin/*' \) -exec chmod +x {} + 2>/dev/null || true
fi

# what the new version installs that this machine does not have
missing=""
if [[ -f "$tmp/zenworks/install" ]]; then
  wanted=$(sed -n '/^PACKAGES=(/,/^)/p' "$tmp/zenworks/install" | sed 's/#.*//' | tr -s ' \t' '\n' | grep -v -e '^PACKAGES=($' -e '^)$' -e '^$' || true)
  for p in $wanted; do pacman -Qq "$p" >/dev/null 2>&1 || missing+="$p "; done
fi

if [[ -n "$dry" ]]; then
  echo "update: $changed file(s) would change (nothing was)"
else
  echo "update: $changed file(s) changed — the shell reloads on its own"
fi
if [[ -n "$missing" ]]; then
  echo "update: packages to install: $missing"
  # run from the shell, there is no terminal to read that in
  [[ -t 1 ]] || notify-send -a ZENWORKS "Updated — some packages are needed" "Install with ceres or paru: $missing" 2>/dev/null || true
fi
exit 0
