#!/usr/bin/env bash
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE CHECKUP — what an audit of this shell looks for, as one run. Oracle's
# Health section starts it and reads it; oracle.js' readCheckup is the parser.
#
#     doctor.sh <shell dir> [qs pid, default the caller] <launch epoch> ["tool names"]
#
# One `key<TAB>value` line per fact, nothing else on stdout. Every check is
# read-only: nothing here touches settings, state or the running shell.

dir=$1 pid=${2:-$PPID} since=$3 tools=${4:-}
cd "$dir" || exit 1

# The suite, as `node oracle/test.js` prints it: the last line is the verdict
# and every FAIL line names a suite.
if command -v node >/dev/null; then
  out=$(node oracle/test.js 2>&1)
  printf 'tests\t%s\n' "$(printf '%s\n' "$out" | grep -E 'checks (pass|FAILED)' | tail -1 | sed 's/^ *//')"
  printf 'testfail\t%s\n' "$(printf '%s\n' "$out" | awk '$1 == "FAIL" { print $2 }' | paste -sd, -)"
else
  printf 'tests\tnode is not installed\n'
fi

# Probes left behind: a `// PROBE` override or a console line tagged PROBE.
# The pattern is spelled in two halves so this script never finds itself.
pat='(//|")\s*PRO''BE\b'
printf 'probes\t%s\n' "$(grep -rlE "$pat" --include='*.qml' --include='*.js' . 2>/dev/null \
  | grep -v '^./oracle/tests/' | sed 's|^\./||' | paste -sd, -)"

# A .js changed since the shell started may still be the old one after a
# reload (the engine caches imported scripts) — only a restart is sure.
printf 'stale\t%s\n' "$(find . -name '*.js' -not -path './scripts/*' -not -path './oracle/tests/*' -not -path './oracle/test.js' -newermt "@$since" 2>/dev/null \
  | sed 's|^\./||' | sort | paste -sd, -)"

# Resident memory, straight from the kernel.
# what the shell stands on now, against what the last clean preflight ran on
printf 'stack\t%s\n' "$(sh scripts/stack.sh 2>/dev/null)"
printf 'stamp\t%s\n' "$(head -1 "${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/preflight-stamp" 2>/dev/null)"

# Hyprland's own complaints about the config: errors, and what the running
# Hyprland calls deprecated (0.57's deprecated-config) — the next release's
# breakage, announced while the old form still works. JSON on one line.
printf 'hyprerr\t%s\n' "$(hyprctl -j configerrors 2>/dev/null | tr -d '\n\t')"
printf 'hyprdep\t%s\n' "$(hyprctl -j deprecated-config 2>/dev/null | tr -d '\n\t')"

# The tools the shell calls out to, by the names oracle hands in (the list,
# with what each is for and where it comes from, is oracle.js TOOLS):
# name:1 if it is on PATH, name:0 if not; a py:NAME python module, if
# python3 can import it.
printf 'tools\t%s\n' "$(for t in $tools; do
  case $t in
    py:*) if python3 -c "import ${t#py:}" >/dev/null 2>&1; then printf '%s:1\n' "${t#py:}"; else printf '%s:0\n' "${t#py:}"; fi ;;
    pkg:*) if pacman -T "${t#pkg:}" >/dev/null 2>&1; then printf '%s:1\n' "${t#pkg:}"; else printf '%s:0\n' "${t#pkg:}"; fi ;;
    *) if command -v "$t" >/dev/null 2>&1; then printf '%s:1\n' "$t"; else printf '%s:0\n' "$t"; fi ;;
  esac
done | paste -sd, -)"

printf 'rss\t%s\n' "$(awk '/^VmRSS:/ { print $2 }' "/proc/$pid/status" 2>/dev/null)"

# The children, sampled for two seconds. Present in every sample means held
# open (a watcher, an inhibitor); anything else was spawned while we looked,
# which is what a poller does — and what a leftover probe did every 400ms.
for _ in $(seq 20); do
  ps --ppid "$pid" -o pid=,args= 2>/dev/null
  echo '--'
  sleep 0.1
done | awk '
  function base(p) { sub(/.*\//, "", p); return p }
  $0 == "--" { n++; next }
  {
    # A script run by its interpreter is named by the script, not "bash".
    nm = base($2)
    if (nm ~ /^(ba|z|da)?sh$|^python3?$|^node$/ && $3 != "" && $3 !~ /^-/) nm = base($3)
    seen[$1]++; name[$1] = nm
  }
  END {
    for (p in seen) {
      if (seen[p] >= n) held = held (held ? "," : "") name[p]
      else spawned = spawned (spawned ? "," : "") name[p]
    }
    printf "held\t%s\nspawned\t%s\n", held, spawned
  }'

# The log since the shell started: errors, and warnings counted apart.
# Known noise (scripts/lognoise.txt, preflight reads it too) is not counted.
log=$(qs log --pid "$pid" 2>/dev/null || qs log 2>/dev/null)
noise=$(sed '/^#/d; /^[[:space:]]*$/d' scripts/lognoise.txt 2>/dev/null)
[ -n "$noise" ] && log=$(printf '%s\n' "$log" | grep -vE -f <(printf '%s\n' "$noise"))
printf 'errors\t%s\n' "$(printf '%s\n' "$log" | grep -c 'ERROR')"
printf 'warnings\t%s\n' "$(printf '%s\n' "$log" | grep -c 'WARN')"
printf 'lasterror\t%s\n' "$(printf '%s\n' "$log" | grep 'ERROR' | tail -1 \
  | sed 's/\x1b\[[0-9;]*m//g; s/^ *ERROR *//' | cut -c1-160)"
