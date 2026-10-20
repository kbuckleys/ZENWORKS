#!/bin/sh
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# DARK OR LIGHT, FOR GTK — run by morpheus/ThemeSync.qml whenever the
# theme's mode changes (and once at start). Every write is skipped when it
# would change nothing.
#
#   gtkscheme.sh prefer-dark|prefer-light
#
# libadwaita hears gsettings' color-scheme live, through the portal; GTK 3
# reads settings.ini's gtk-application-prefer-dark-theme as it starts.
#
# GTK 3 takes the shell's colors (gtk-3.0/colors.css) only through
# adw-gtk3, the libadwaita look ported to GTK 3 (pacman: adw-gtk-theme):
# plain Adwaita there paints with literals. So when it is installed, its
# light or dark cut becomes the GTK theme; when not, gtk-theme is left be.

scheme="$1"
case "$scheme" in
	prefer-light) dark=0 ;;
	prefer-dark) dark=1 ;;
	*) exit 2 ;;
esac
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"

theme=
for d in "${XDG_DATA_HOME:-$HOME/.local/share}/themes" "$HOME/.themes" /usr/share/themes; do
	[ -d "$d/adw-gtk3" ] && { theme=adw-gtk3; [ $dark = 1 ] && theme=adw-gtk3-dark; break; }
done

if command -v gsettings >/dev/null 2>&1; then
	s=org.gnome.desktop.interface
	[ "$(gsettings get $s color-scheme 2>/dev/null)" = "'$scheme'" ] || gsettings set $s color-scheme "$scheme"
	[ -z "$theme" ] || [ "$(gsettings get $s gtk-theme 2>/dev/null)" = "'$theme'" ] || gsettings set $s gtk-theme "$theme"
fi

# write $1=$2 into settings.ini $3, under [Settings]; skipped when it says so
ini() {
	grep -qxF "$1=$2" "$3" && return
	if grep -q "^$1=" "$3"; then
		awk -v k="$1" -v v="$1=$2" 'index($0, k "=") == 1 { print v; next } { print }' "$3" > "$3.scheme.tmp"
	else
		awk -v v="$1=$2" '{ print } /^\[Settings\]/ { print v }' "$3" > "$3.scheme.tmp"
	fi
	mv -f "$3.scheme.tmp" "$3"
}

# fontsync.sh rewrites the same files, and both run as the shell starts
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/zen-gtk-settings.lock"
flock 9 2>/dev/null
for f in "$cfg/gtk-3.0/settings.ini" "$cfg/gtk-4.0/settings.ini"; do
	[ -f "$f" ] || continue
	ini gtk-application-prefer-dark-theme $dark "$f"
	[ -z "$theme" ] || ini gtk-theme-name "$theme" "$f"
done
exit 0
