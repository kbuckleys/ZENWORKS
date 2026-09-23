#!/usr/bin/env bash
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# CERES — the package list, and the questions asked of it.
#
#   ceres.sh rows                   build (or reuse) the whole list
#   ceres.sh search <all|installed> [query]
#   ceres.sh info <pkg> [repo]      pacman/paru's own record for one package
#
# THE LIST NEVER ENTERS QML. The repos and the AUR together are some 135,000
# packages; ceres asks this for the few hundred that match and draws those.
# It is ZENU's gawk pass (one read of every source, joined in one process),
# emitting tab-separated fields instead of padded columns:
#
#   state  name  size  repo  version
#
# state is avail / explicit / dep; size is bytes (installed size for what is
# installed, download size for what is not; 0 when nothing knows, which is
# every AUR package before it is built).
#
# CACHED against the mtimes of the databases it was built from, so the second
# search of a session costs a grep, not a rebuild.

set -u
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/ceres"
ROWS="$CACHE/rows.tsv"
# ── THE AUR'S NAMES, OUR OWN COPY ────────────────────────────────────────
# This read paru's completion cache, ~/.cache/paru/packages.aur, which paru
# writes when IT decides to — and which is simply absent after paru has been
# reinstalled or its cache cleared: the AUR vanished from the list with no
# error anywhere. So ceres keeps its own, from the AUR's published list,
# refreshed every three days; paru's is only a fallback for when the AUR
# cannot be reached.
AUR="$CACHE/aur-names"
PARU_AUR="$HOME/.cache/paru/packages.aur"

aur_list() {
  mkdir -p "$CACHE"
  if [ "${1:-}" != force ] && [ -s "$AUR" ] && [ -z "$(find "$AUR" -mmin +4320 2>/dev/null)" ]; then return 0; fi
  if curl -fsS --max-time 60 https://aur.archlinux.org/packages.gz 2>/dev/null \
       | gunzip 2>/dev/null | grep -v '^#' > "$AUR.$$" && [ -s "$AUR.$$" ]; then
    mv -f "$AUR.$$" "$AUR"
  else
    rm -f "$AUR.$$"
    [ -s "$AUR" ] || { [ -s "$PARU_AUR" ] && cp -f "$PARU_AUR" "$AUR"; }
  fi
  return 0
}

stamp() {
  stat -c %Y /var/lib/pacman/local /var/lib/pacman/sync "$AUR" 2>/dev/null | tr '\n' ' '
}

build() {
  mkdir -p "$CACHE"
  aur_list
  # AUR descriptions are refreshed after 12h anyway; one untouched for a week
  # is a package nobody is looking at, and would otherwise stay forever
  find "$CACHE/aur-si" -type f -mmin +10080 -delete 2>/dev/null
  local s part aur
  s="$(stamp)"
  if [ -r "$ROWS" ] && [ "$(cat "$ROWS.stamp" 2>/dev/null)" = "$s" ]; then return 0; fi
  aur="$AUR"; [ -r "$aur" ] || aur=/dev/null
  part="$ROWS.$$"
  # ARGIND is positional, so each stream keeps its index even when empty.
  # LC_ALL=C: names are ASCII and byte-wise is measurably faster here.
  LC_ALL=C gawk -F'[ \t]+' '
    ARGIND == 1 { inst[$1] = $2; next }            # pacman -Q      name ver
    ARGIND == 2 { expl[$1] = 1; next }             # pacman -Qeq    name
    ARGIND == 3 { isize[$1] = $2; next }           # expac -Q       name size
    ARGIND == 4 { dsize[$1] = $2; sver[$1] = $3; next }  # expac -S name dl ver
    ARGIND == 5 {                                  # pacman -Sl     repo name ver
      if ($2 in seen) next
      seen[$2] = 1
      row($2, $1, $3); next
    }
    ARGIND == 6 {                                  # the AUR name list
      if ($1 in seen) next
      seen[$1] = 1
      row($1, "aur", ""); next
    }
    function row(n, repo, ver,   st, sz, v) {
      if (!(n in inst)) { st = "avail"; sz = dsize[n] + 0; v = ver }
      else { st = (n in expl) ? "explicit" : "dep"; sz = isize[n] + 0; v = inst[n] }
      printf "%s\t%s\t%d\t%s\t%s\n", st, n, sz, repo, v
    }
    END {
      # installed from nowhere any database knows: -U, or dropped upstream
      for (n in inst) if (!(n in seen))
        printf "%s\t%s\t%d\tlocal\t%s\n", ((n in expl) ? "explicit" : "dep"), n, isize[n] + 0, inst[n]
    }' \
    <(pacman -Q 2>/dev/null) \
    <(pacman -Qeq 2>/dev/null) \
    <(expac -Q '%n %m' 2>/dev/null) \
    <(expac -S '%n %k %v' 2>/dev/null) \
    <(pacman -Sl 2>/dev/null) \
    "$aur" > "$part" \
  && mv -f "$part" "$ROWS" && printf '%s' "$s" > "$ROWS.stamp"
  rm -f "$part"
}

case "${1:-}" in
  rows)
    build
    ;;
  aur)
    # refresh the AUR list now, whatever its age, and the rows with it
    aur_list force
    build
    ;;
  search)
    mode="${2:-all}"; q="${3:-}"
    build
    if [ -z "$q" ]; then
      # Nothing typed: what you chose to install, or everything installed.
      # The whole catalogue in arbitrary order is not an answer to anything.
      if [ "$mode" = installed ]; then awk -F'\t' '$1 != "avail"' "$ROWS"
      else awk -F'\t' '$1 == "explicit"' "$ROWS"; fi | LC_ALL=C sort -t$'\t' -k2,2 | head -n 500
    else
      # THE EXACT NAME FIRST, found on its own. Typing "go" is asking for
      # go; left to fzf it was not even in the first 300, because the
      # length tiebreak measures the whole ROW and a repo package's row
      # (size, repo, version) is longer than an AUR one's.
      #
      # Then fzf, ranking by the NAME only (--nth 2) and breaking ties by
      # position — the list is built repos first, so an official package
      # outranks an AUR one that matches as well.
      src() { if [ "$mode" = installed ]; then awk -F'\t' '$1 != "avail"' "$ROWS"; else cat "$ROWS"; fi; }
      src | awk -F'\t' -v q="$q" '$2 == q'
      src | fzf --filter "$q" --delimiter $'\t' --nth 2 --tiebreak=begin,index \
          | awk -F'\t' -v q="$q" '$2 != q' | head -n 300
    fi
    ;;
  info)
    pkg="${2:-}"; repo="${3:-}"
    [ -n "$pkg" ] || exit 0
    # `paru -Si` is a network round trip; half a day of cache, and stale
    # beats blank when the AUR is unreachable. ZENU's rule, kept.
    aur_info() {
      local dir="$CACHE/aur-si" f out
      f="$dir/$1"
      if [ -s "$f" ] && [ -z "$(find "$f" -mmin +720 2>/dev/null)" ]; then cat "$f"; return 0; fi
      mkdir -p "$dir"
      if out=$(paru -Si -- "$1" 2>/dev/null) && [ -n "$out" ]; then
        printf '%s\n' "$out" > "$f.$$" && mv -f "$f.$$" "$f"; printf '%s\n' "$out"
      elif [ -s "$f" ]; then cat "$f"; fi
    }
    case "$repo" in
      update) pacman -Si -- "$pkg" 2>/dev/null || aur_info "$pkg" ;;
      aur)    pacman -Qi -- "$pkg" 2>/dev/null || aur_info "$pkg" ;;
      *)      pacman -Qi -- "$pkg" 2>/dev/null || pacman -Si -- "$pkg" 2>/dev/null || aur_info "$pkg" ;;
    esac
    ;;
  *)
    echo "usage: ceres.sh rows | aur | search <all|installed> [query] | info <pkg> [repo]" >&2
    exit 2
    ;;
esac
