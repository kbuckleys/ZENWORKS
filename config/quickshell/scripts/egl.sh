# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# SOURCED, NOT RUN — by scripts/launch.sh (the shell).
#
# NVIDIA's EGL only, ONLY ON A MACHINE THAT IS ALL NVIDIA. glvnd otherwise
# loads Mesa's EGL as well, and Mesa brings its gallium/LLVM rasterizer into
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
