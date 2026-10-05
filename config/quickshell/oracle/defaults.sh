#!/usr/bin/env bash
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# WHAT IS INSTALLED, AND WHAT OPENS WHAT — oracle's Defaults section starts
# this and oracle.js' readDefaultsScan is the parser.
#
#     defaults.sh <mime type>... [-- <program name>...]
#
# One record per line, fields split by a TAB, nothing else on stdout:
#
#     app       <id> <name> <mime;types;> <Categories;> <first word of Exec> <Terminal>
#     default   <mime type> <id that opens it now, or empty>
#     terminal  <id xdg-terminal-exec would pick from xdg-terminals.list>
#     bin       <program name, of the ones after --, that is on PATH>
#
# Read-only. Choosing happens in Oracle, through `gio mime`.

# Every desktop entry along the XDG search path, the first of each id winning
# — which is the user's own copy whenever one exists, as the spec says. The
# same path morpheus/Desktop.qml walks.
dirs=("${XDG_DATA_HOME:-$HOME/.local/share}/applications")
IFS=: read -ra sys <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for d in "${sys[@]}"; do dirs+=("$d/applications"); done

files=()
for d in "${dirs[@]}"; do
  [ -d "$d" ] || continue
  for f in "$d"/*.desktop; do [ -f "$f" ] && files+=("$f"); done
done

# Only the [Desktop Entry] group: an action group has its own Name= and Exec=,
# and reading those would name a browser "New Private Window". Hidden=true is
# the spec's word for "deleted", so it is skipped outright; NoDisplay is not —
# a handler that keeps out of the launcher (picasso-view) is still a handler.
if [ ${#files[@]} -gt 0 ]; then
  awk '
    FNR == 1 {
      flush()
      id = FILENAME; sub(/.*\//, "", id)
      grp = ""; name = ""; mime = ""; cats = ""; exe = ""; hidden = 0; term = "false"
    }
    /^\[/ { grp = $0; next }
    grp != "[Desktop Entry]" { next }
    /^Name=/       && name == "" { name = substr($0, 6) }
    /^MimeType=/   { mime = substr($0, 10) }
    /^Categories=/ { cats = substr($0, 12) }
    /^Exec=/       && exe == "" { split(substr($0, 6), w, " "); exe = w[1]; gsub(/"/, "", exe) }
    /^Hidden=true/ { hidden = 1 }
    /^Terminal=true/ { term = "true" }
    function flush() {
      if (id == "" || hidden || (id in seen)) return
      seen[id] = 1
      printf "app\t%s\t%s\t%s\t%s\t%s\t%s\n", id, (name == "" ? id : name), mime, cats, exe, term
    }
    END { flush() }
  ' "${files[@]}"
fi

bins=0
for m in "$@"; do
  if [ "$m" = "--" ]; then bins=1; continue; fi
  if [ $bins = 1 ]; then
    command -v "$m" >/dev/null 2>&1 && printf 'bin\t%s\n' "$m"
  else
    printf 'default\t%s\t%s\n' "$m" "$(xdg-mime query default "$m" 2>/dev/null)"
  fi
done

# xdg-terminal-exec's own list: the first entry that is not a comment.
list="${XDG_CONFIG_HOME:-$HOME/.config}/xdg-terminals.list"
printf 'terminal\t%s\n' "$( [ -f "$list" ] && grep -v '^[[:space:]]*\(#\|$\)' "$list" | head -1 | tr -d '[:space:]')"
