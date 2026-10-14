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
# NOT THE CONFIG ON THE MAINTAINER'S MACHINE: there the live config is AHEAD
# of what is published, and laying it over would roll it back. A machine with
# the package checkout (~/Projects/ZENWORKS, sync-package.sh's) keeps its
# config (--force lays it anyway) — and still gets what is missing, below.
#
# WHAT IS MISSING IS INSTALLED (user, 2026-10-13): the packages the published
# installer lists that this machine lacks, and what ZENWORKS builds itself
# (quickshell/pkgbuilds/<name>, for a package whose AUR recipe is broken —
# none at present) that is not installed. Not here — a job has no terminal for sudo — but by ceres,
# which asks for the password on its own card: this writes what is needed to
# $XDG_RUNTIME_DIR/zenworks-update.json, and the shell (OracleManager) reads
# it, removes it, and hands it to ceres. By hand, it is printed instead.
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

# run from the shell, a failure is said where it can be read: a notification
said() { [[ -t 1 ]] || notify-send -a ZENWORKS "Update failed" "$1" 2>/dev/null || true; echo "update: $1" >&2; }
trap 'said "stopped at line $LINENO (exit $?)"' ERR

maintained=""
if [[ -z "$force" && -d "$HOME/Projects/ZENWORKS/config" ]]; then
  maintained=1
  echo "update: this machine maintains ZENWORKS (~/Projects/ZENWORKS) — its config is ahead of the published one and is left as it is (--force lays it anyway); what is missing is still installed"
fi

for tool in git rsync; do
  command -v "$tool" >/dev/null || { said "$tool is needed"; exit 4; }
done

# the scratch directory, and the promise that it goes whatever happens
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zenworks-update.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT INT TERM

echo "update: fetching $REPO"
git clone --quiet --depth 1 -- "$REPO" "$tmp/zenworks" || { said "could not fetch $REPO"; exit 5; }
rev="$(git -C "$tmp/zenworks" log -1 --format='%h %cs %s' 2>/dev/null || true)"
echo "update: published version: ${rev:-unknown}"

changed=0
n=0
for d in "${CONFIGS[@]}"; do
  n=$((n + 1))
  [[ -n "$maintained" ]] && continue
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

if [[ -z "$dry" && -z "$maintained" ]]; then
  # a repository uploaded through GitHub's web page loses its executable
  # bits: the scripts and the launchers, set again (as the installer does)
  find "$CONFIG/quickshell" "$CONFIG/hypr" "$CONFIG/xdg-desktop-portal-termfilechooser" \
    -type f \( -name '*.sh' -o -name '*.py' -o -path '*/bin/*' \) -exec chmod +x {} + 2>/dev/null || true
fi

# what the new version installs that this machine does not have
missing=()
if [[ -f "$tmp/zenworks/install" ]]; then
  wanted=$(sed -n '/^PACKAGES=(/,/^)/p' "$tmp/zenworks/install" | sed 's/#.*//' | tr -s ' \t' '\n' | grep -v -e '^PACKAGES=($' -e '^)$' -e '^$' || true)
  for p in $wanted; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
fi
# and what ZENWORKS builds itself, from the config just laid
build=()
for dir in "$CONFIG"/quickshell/pkgbuilds/*/; do
  [[ -f "$dir/PKGBUILD" ]] || continue
  name="$(basename -- "$dir")"
  pacman -Qq "$name" >/dev/null 2>&1 || build+=("${dir%/}")
done

if [[ -n "$dry" ]]; then
  echo "update: $changed file(s) would change (nothing was)"
elif [[ -n "$maintained" ]]; then
  echo "update: config left as it is"
else
  echo "update: $changed file(s) changed — the shell reloads on its own"
fi
(( ${#missing[@]} )) && echo "update: packages to install: ${missing[*]}"
(( ${#build[@]} )) && echo "update: to build: ${build[*]}"

# for the shell (not by hand, not a dry run): what ceres is to install —
# read once and removed (OracleManager), so nothing stays
if [[ -z "$dry" && ! -t 1 ]] && (( ${#missing[@]} + ${#build[@]} )); then
  out="${XDG_RUNTIME_DIR:-/tmp}/zenworks-update.json"
  list() { local first=1; for x in "$@"; do (( first )) || printf ','; first=0; printf '"%s"' "$x"; done; }
  { printf '{"missing":['; list "${missing[@]}"; printf '],"build":['; list "${build[@]}"; printf ']}\n'; } > "$out.part"
  mv -f -- "$out.part" "$out"
fi
exit 0
