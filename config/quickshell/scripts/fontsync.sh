#!/bin/sh
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# ORACLE'S FONTS, CARRIED OUT OF THE SHELL — run by morpheus/ThemeSync.qml
# whenever Font or Monospace font changes (and once at start). Every write
# is skipped when it would change nothing, so a start costs no reloads.
#
#   fontsync.sh GTKFONT MONOGTK MONOFAMILY MONOWEIGHT MONOPT FONTCONFIG
#
# GTKFONT / MONOGTK  Pango descriptions ("SF Pro Text Medium 12")
# MONOFAMILY ...     kitty's face, CSS weight, size in points
# FONTCONFIG         the text of conf.d/50-oracle-fonts.conf

gtk="$1"; monogtk="$2"; mono="$3"; monow="$4"; monopt="$5"; fcxml="$6"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"

# write $2 to $1 unless it says that already; status 0 when written
put() {
	printf '%s' "$2" | cmp -s - "$1" 2>/dev/null && return 1
	mkdir -p "${1%/*}" && printf '%s' "$2" > "$1.tmp" && mv -f "$1.tmp" "$1"
}

# ── kitty: ~/.config/zenworks/kitty/kitty.conf includes font.conf; SIGUSR1 rereads it ──
# The style is fontconfig's own name for that weight of the family — "Semibold"
# in one, "SemiBold" in the next — so kitty matches it exactly.
case "$monow" in
	300) fcw=50 ;; 400) fcw=80 ;; 500) fcw=100 ;; 600) fcw=180 ;; 700) fcw=200 ;; *) fcw=80 ;;
esac
style=$(fc-match -f '%{style[0]}' "$mono:weight=$fcw" 2>/dev/null)
kconf="# Written by the shell (morpheus/ThemeSync.qml, scripts/fontsync.sh) from
# oracle's Monospace font. Edits here are overwritten.
font_family      family=\"$mono\"${style:+ style=\"$style\"}
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        $monopt
"
put "$cfg/zenworks/kitty/font.conf" "$kconf" && pkill -USR1 -x kitty

# ── GTK 3 and 4: settings.ini's gtk-font-name ──
# gtkscheme.sh rewrites the same files, and both run as the shell starts
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/zen-gtk-settings.lock"
flock 9 2>/dev/null
for f in "$cfg/gtk-3.0/settings.ini" "$cfg/gtk-4.0/settings.ini"; do
	[ -f "$f" ] || continue
	grep -qxF "gtk-font-name=$gtk" "$f" && continue
	if grep -q '^gtk-font-name=' "$f"; then
		awk -v v="gtk-font-name=$gtk" '/^gtk-font-name=/ { print v; next } { print }' "$f" > "$f.tmp"
	else
		awk -v v="gtk-font-name=$gtk" '{ print } /^\[Settings\]/ { print v }' "$f" > "$f.tmp"
	fi
	mv -f "$f.tmp" "$f"
done

# ── gsettings: what GTK apps, the portal and libadwaita read live ──
if command -v gsettings >/dev/null 2>&1; then
	s=org.gnome.desktop.interface
	for kv in "font-name=$gtk" "document-font-name=$gtk" "monospace-font-name=$monogtk"; do
		k="${kv%%=*}"; v="${kv#*=}"
		[ "$(gsettings get $s "$k" 2>/dev/null)" = "'$v'" ] || gsettings set $s "$k" "$v"
	done
fi

# ── fontconfig: sans-serif, system-ui and monospace (new processes) ──
put "$cfg/fontconfig/conf.d/50-oracle-fonts.conf" "$fcxml"
exit 0
