#!/bin/sh
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE ONE WAY THIS SHELL IS STARTED — autostart, oracle's Restart, icarus'
# restart. Arguments go straight to qs (-n, -d).
#
# The GL vendor: scripts/egl.sh, shared with iris.
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

exec qs "$@"
