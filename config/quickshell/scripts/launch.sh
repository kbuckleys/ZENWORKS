#!/bin/sh
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE ONE WAY THIS SHELL IS STARTED — autostart, oracle's Restart, icarus'
# restart. Arguments go straight to qs (-n, -d).
#
# The GL vendor: scripts/egl.sh.
. "$(dirname "$(readlink -f "$0")")/egl.sh"

# NO MALLOC_ARENA_MAX. It was here, measured as saving RAM — but quickshell is
# built with jemalloc, which replaces glibc's allocator outright, so a glibc
# tunable changes nothing and the "saving" was noise between two runs. The
# real savings were Mesa above and terminus' leaked windows.

# THE BIGGEST PICTURE QT WILL DECODE, in megabytes of pixels. Its own default
# is 256, and past it an image is refused outright — with a size asked for or
# not, since the png reader decodes the whole file before it scales. A
# 15119x8504 background (514 MB as RGBA) was a black screen on the desktop and
# a 1600px stand-in in picasso. 2048 is ~530 megapixels; nothing decodes that
# big unless it is opened, and picasso's viewer and background both ask for
# screen-sized copies first.
export QT_IMAGEIO_MAXALLOC=2048

# Qt's Wayland text-input-v3 warns at every window open that its idea of the
# focused surface lags the compositor's ("Trying to disable … but … is
# focused"). Qt's bookkeeping, nothing the shell can act on: it was the
# whole of Health's warning count after a clean start (2026-10-18). Kept in
# scripts/lognoise.txt too, for a shell started some other way.
export QT_LOGGING_RULES="${QT_LOGGING_RULES:+$QT_LOGGING_RULES;}qt.qpa.wayland.textinput.warning=false"

# THE COMPILED-QML CACHE (~/.cache/quickshell/qmlcache). Qt writes a .qmlc
# for every version of every file it compiles and never deletes one: 95 MB
# on 2026-10-17, 200 MB and 5615 files a day later. Stale ones are only
# skipped, never harmful, so this is upkeep: after Qt, quickshell or
# Hyprland change (scripts/stack.sh) the whole cache goes — none of it
# matches the new Qt anyway — and otherwise anything not read in two weeks.
cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
stack=$(sh "$(dirname "$(readlink -f "$0")")/stack.sh" 2>/dev/null)
if [ -n "$stack" ] && [ "$(cat "$cache/qmlcache.stack" 2>/dev/null)" != "$stack" ]; then
  rm -rf "$cache/qmlcache"
  mkdir -p "$cache" && printf '%s\n' "$stack" > "$cache/qmlcache.stack"
elif [ -d "$cache/qmlcache" ]; then
  find "$cache/qmlcache" -type f -atime +14 -delete 2>/dev/null
fi


# FLATPAK'S APPS IN THE LAUNCHER. Flatpak exports their desktop entries under
# its own share directories; /etc/profile.d/flatpak.sh adds them for a login
# shell, and a session that never ran one — this one — never saw them. Set
# HERE, where the shell is always started (user, 2026-10-15: "installed
# flatpaks don't generate .desktop entries?"), so a restart is enough, and
# everything the shell launches inherits it. Hyprland's base.lua sets the
# same for what it starts itself. Harmless with no Flatpak: nothing is there.
d="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for x in /var/lib/flatpak/exports/share "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share"; do
  case ":$d:" in *":$x:"*) ;; *) d="$x:$d" ;; esac
done
export XDG_DATA_DIRS="$d"

exec qs "$@"
