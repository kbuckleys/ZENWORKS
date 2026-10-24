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
#   gtkscheme.sh prefer-dark|prefer-light [reload|now]
#
# libadwaita hears gsettings' color-scheme live, through the portal; GTK 3
# reads settings.ini's gtk-application-prefer-dark-theme as it starts.
#
# GTK 3 takes the shell's colors (gtk-3.0/colors.css) only through
# adw-gtk3, the libadwaita look ported to GTK 3 (pacman: adw-gtk-theme):
# plain Adwaita there paints with literals. When it is not installed,
# gtk-theme is left be and gtk-3.0/gtk.css @imports colors.css.
#
# LIVE, THROUGH A THEME OF OUR OWN. A user gtk.css is read once, as an app
# starts, so a running GTK 3 app kept the colors it opened with — and
# Electron (Claude Desktop, VS Code...) tells dark from light by that
# background, so it never switched (2026-10-24; Chrome itself asks the
# portal, which is why Brave did). A theme is read again whenever
# gtk-theme names another one. So the colors live in a theme,
# zenworks-a or zenworks-b in ~/.local/share/themes: adw-gtk3's light or
# dark cut, then colors.css. `reload` (ThemeSync: colors.css or the mode
# changed) writes the slot not worn and names it; without it the slot
# worn is only checked, so a shell start repaints nothing. gtk-dark.css
# says the same as gtk.css: settings.ini's stale prefer-dark (read at an
# app's start, never again) must not pick a cut of its own.
#
# The slot carries a gtk-4.0 cut as well (adw-gtk3's own, then
# gtk-4.0/colors.css): plain GTK 4 apps (transmission-gtk, gtkmm) take
# their theme from gtk-theme too, and a slot without one dropped them to
# GTK's Default, all literals: dark or light, none of the shell's colors
# (2026-10-24). libadwaita apps ignore the theme and keep gtk-4.0/gtk.css.
#
# `now` sets color-scheme alone, the moment the mode flips: the portal's
# listeners (libadwaita, Chrome, Electron) switch at once, and the slot
# follows with `reload` once colors.css has landed. Alone it repaints no
# GTK 3 app, so nothing reads the old slot as the new mode.

scheme="$1"
case "$scheme" in
	prefer-light) dark=0 ;;
	prefer-dark) dark=1 ;;
	*) exit 2 ;;
esac
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
s=org.gnome.desktop.interface
# before any slot is touched: `reload` follows and writes the slot itself
if [ "$2" = now ]; then
	[ "$(gsettings get $s color-scheme 2>/dev/null)" = "'$scheme'" ] || gsettings set $s color-scheme "$scheme"
	exit 0
fi

data="${XDG_DATA_HOME:-$HOME/.local/share}"
base=
for d in "$data/themes" "$HOME/.themes" /usr/share/themes; do
	[ -f "$d/adw-gtk3/gtk-3.0/gtk.css" ] && { base=adw-gtk3; [ $dark = 1 ] && base=adw-gtk3-dark; base="$d/$base/gtk-3.0/gtk.css"; break; }
done

# gtk-3.0/gtk.css: colors.css itself only when no theme carries it
user="$cfg/gtk-3.0/gtk.css"
if [ -n "$base" ]; then
	want='/* The shell'"'"'s colors reach GTK 3 through its zenworks-a/-b theme (scripts/gtkscheme.sh). */'
else
	want='/* The shell'"'"'s theme: colors.css is written by quickshell (morpheus/ThemeSync.qml). */
@import url("colors.css");'
fi
[ -d "$cfg/gtk-3.0" ] && [ "$(cat "$user" 2>/dev/null)" != "$want" ] && printf '%s\n' "$want" > "$user"

theme=
if [ -n "$base" ]; then
	css="@import url(\"file://$base\");
@import url(\"file://$cfg/gtk-3.0/colors.css\");"
	base4="${base%/gtk-3.0/gtk.css}/gtk-4.0/gtk.css"
	css4=
	[ -f "$base4" ] && css4="@import url(\"file://$base4\");
@import url(\"file://$cfg/gtk-4.0/colors.css\");"
	worn=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
	case "$worn" in
		zenworks-a|zenworks-b) theme=$worn ;;
	esac
	# a slot that already says it is kept, unless the colors changed
	if [ -z "$theme" ] || [ "$2" = reload ] || [ "$(cat "$data/themes/$theme/gtk-3.0/gtk.css" 2>/dev/null)" != "$css" ] \
		|| [ "$(cat "$data/themes/$theme/gtk-4.0/gtk.css" 2>/dev/null)" != "$css4" ]; then
		theme=zenworks-a; [ "$worn" = zenworks-a ] && theme=zenworks-b
		mkdir -p "$data/themes/$theme/gtk-3.0"
		printf '%s\n' "$css" > "$data/themes/$theme/gtk-3.0/gtk.css"
		printf '%s\n' "$css" > "$data/themes/$theme/gtk-3.0/gtk-dark.css"
		if [ -n "$css4" ]; then
			mkdir -p "$data/themes/$theme/gtk-4.0"
			printf '%s\n' "$css4" > "$data/themes/$theme/gtk-4.0/gtk.css"
			printf '%s\n' "$css4" > "$data/themes/$theme/gtk-4.0/gtk-dark.css"
		else
			rm -rf "$data/themes/$theme/gtk-4.0"
		fi
		printf '[Desktop Entry]\nType=X-GNOME-Metatheme\nName=%s\nComment=The shell'"'"'s colors over adw-gtk3 (scripts/gtkscheme.sh)\n' "$theme" > "$data/themes/$theme/index.theme"
	fi
fi

if command -v gsettings >/dev/null 2>&1; then
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
	# GTK 3 under a zenworks slot: the slot is the mode, and the flag stays 0.
	# A running app never rereads it, and Electron counts a stale 1 as dark
	# over the slot's light colors (Claude Desktop flashed light, then back)
	if [ -n "$base" ] && [ "$f" = "$cfg/gtk-3.0/settings.ini" ]; then
		ini gtk-application-prefer-dark-theme 0 "$f"
	else
		ini gtk-application-prefer-dark-theme $dark "$f"
	fi
	[ -z "$theme" ] || ini gtk-theme-name "$theme" "$f"
done
exit 0
