#!/usr/bin/env bash
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE CHECKUP — what an audit of this shell looks for, as one run. Oracle's
# Health section starts it and reads it; oracle.js' readCheckup is the parser.
#
#     doctor.sh <shell dir> [qs pid, default the caller] <launch epoch>
#
# One `key<TAB>value` line per fact, nothing else on stdout. Every check is
# read-only: nothing here touches settings, state or the running shell.

dir=$1 pid=${2:-$PPID} since=$3
cd "$dir" || exit 1

# The suite, as `node scripts/test.js` prints it: the last line is the verdict
# and every FAIL line names a suite.
if command -v node >/dev/null; then
  out=$(node scripts/test.js 2>&1)
  printf 'tests\t%s\n' "$(printf '%s\n' "$out" | grep -E 'checks (pass|FAILED)' | tail -1 | sed 's/^ *//')"
  printf 'testfail\t%s\n' "$(printf '%s\n' "$out" | awk '$1 == "FAIL" { print $2 }' | paste -sd, -)"
else
  printf 'tests\tnode is not installed\n'
fi

# Probes left behind: a `// PROBE` override or a console line tagged PROBE.
# The pattern is spelled in two halves so this script never finds itself.
pat='(//|")\s*PRO''BE\b'
printf 'probes\t%s\n' "$(grep -rlE "$pat" --include='*.qml' --include='*.js' . 2>/dev/null \
  | grep -v '^./scripts/tests/' | sed 's|^\./||' | paste -sd, -)"

# A .js changed since the shell started may still be the old one after a
# reload (the engine caches imported scripts) — only a restart is sure.
printf 'stale\t%s\n' "$(find . -name '*.js' -not -path './scripts/*' -newermt "@$since" 2>/dev/null \
  | sed 's|^\./||' | sort | paste -sd, -)"

# Resident memory, straight from the kernel.
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
log=$(qs log --pid "$pid" 2>/dev/null || qs log 2>/dev/null)
printf 'errors\t%s\n' "$(printf '%s\n' "$log" | grep -c 'ERROR')"
printf 'warnings\t%s\n' "$(printf '%s\n' "$log" | grep -c 'WARN')"
printf 'lasterror\t%s\n' "$(printf '%s\n' "$log" | grep 'ERROR' | tail -1 \
  | sed 's/\x1b\[[0-9;]*m//g; s/^ *ERROR *//' | cut -c1-160)"
