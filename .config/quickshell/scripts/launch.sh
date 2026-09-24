#!/bin/sh
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE ONE WAY THIS SHELL IS STARTED — autostart, oracle's Restart, icarus'
# restart. Arguments go straight to qs (-n, -d).
#
# NVIDIA's EGL only, ONLY ON A MACHINE THAT IS ALL NVIDIA. glvnd otherwise
# loads Mesa's EGL as well, and Mesa brings its gallium/LLVM rasteriser into
# the shell — ~108MB of RSS measured, for a driver an NVIDIA-only machine
# never draws with. But pinned on anything else it is fatal: with no NVIDIA
# driver there is then no EGL at all and nothing draws, and on a hybrid laptop
# it would force the shell onto the discrete GPU. So it is decided here, from
# what the kernel reports: every DRM card's PCI vendor must be NVIDIA's 0x10de,
# and the vendor file must exist.
nv=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
vendors=$(cat /sys/class/drm/card*/device/vendor 2>/dev/null | sort -u)
if [ "$vendors" = "0x10de" ] && [ -f "$nv" ]; then
    export __EGL_VENDOR_LIBRARY_FILENAMES="$nv"
fi

# NO MALLOC_ARENA_MAX. It was here, measured as saving RAM — but quickshell is
# built with jemalloc, which replaces glibc's allocator outright, so a glibc
# tunable changes nothing and the "saving" was noise between two runs. The
# real savings were Mesa above and terminus' leaked windows.

exec qs "$@"
