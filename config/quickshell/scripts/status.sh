#!/usr/bin/env bash
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# Privacy/status probe. Emits JSON lines:
#   {"mic":0,"screen":0,"recording":0}
#
# mic       an application is actively capturing audio
# screen    a screencast pipeline is live (portal share, browser call, ...)
# recording wf-recorder is running — the same process the hypr bind toggles
#
#   status.sh          one line, now
#   status.sh watch    a line at start and another whenever the answer
#                      changes, for as long as it runs
#
# WATCH IS WHAT THE BAR RUNS. It used to run the one-shot every two seconds:
# a bash, a pw-dump of the whole graph and a jq, all session long, to answer
# a question whose answer changes a few times a day. Now one pw-mon reports
# graph changes and the dump is only taken when a node has come, gone or
# changed state. wf-recorder is not in the graph unless it records audio, so
# it is still looked for, every five seconds, with one pgrep.

pw_state() {
  # One pw-dump serves both stream checks. Only nodes in the `running` state
  # count; apps that merely hold a stream open sit at idle/suspended and must
  # not light the indicator.
  local dump
  if dump="$(pw-dump 2>/dev/null)"; then
    printf '%s' "$dump" | jq -r '
      [ .[]
        | select(.type == "PipeWire:Interface:Node")
        | select(.info.state == "running")
        | .info.props["media.class"] // ""
      ] as $live
      | [ ($live | map(select(. == "Stream/Input/Audio")) | length | if . > 0 then 1 else 0 end),
          ($live | map(select(startswith("Stream/") and endswith("/Video"))) | length | if . > 0 then 1 else 0 end)
        ] | @tsv
    ' 2>/dev/null
  fi
}

recording() {
  pgrep -x wf-recorder >/dev/null 2>&1 && echo 1 || echo 0
}

line() {
  printf '{"mic":%d,"screen":%d,"recording":%d}\n' "${1:-0}" "${2:-0}" "${3:-0}"
}

if [ "${1:-}" != watch ]; then
  read -r mic screen <<<"$(pw_state)"
  line "$mic" "$screen" "$(recording)"
  exit 0
fi

# ── watch ──────────────────────────────────────────────────────────────────
# Nothing tells this script when the shell is gone: a restart SIGTERMs
# quickshell, and a reload may SIGKILL this. So both halves below watch for
# it themselves — each checks, every pass, that the process that started it
# is still its parent (an orphan is reparented, so a recycled pid cannot
# fool this the way `kill -0` can). A leak here used to leave one pw-mon
# loop behind per restart, a hundred and more of them by the end of a week.
main=$$
parent=$PPID

# Sets $ppid rather than printing it: in a $(...) this would be a subshell,
# and $BASHPID there that subshell's own pid.
ppid_of() {
  ppid=""
  read -r _ _ _ ppid _ <"/proc/$1/stat" 2>/dev/null
}

# pw-mon, restarted if pipewire goes away and comes back. -o/-a keep it from
# printing every property of every node on every change; a pw-mon too old to
# know them falls back to the full output. Without pw-mon at all this still
# runs, as the five-second tick alone.
events() {
  local child opts=(-N)
  alive() { ppid_of "$BASHPID"; [ "$ppid" = "$main" ]; }
  if ! command -v pw-mon >/dev/null 2>&1; then
    while alive; do sleep 5; done
    exit 0
  fi
  pw-mon --help 2>&1 | grep -q -- --hide-params && opts=(-N -o -a)
  trap 'kill "$child" 2>/dev/null; exit 0' TERM INT
  # If the reader is killed outright, pw-mon dies of SIGPIPE at its next
  # line and this loop, seeing itself orphaned, does not start another.
  while alive; do
    pw-mon "${opts[@]}" 2>/dev/null &
    child=$!
    wait "$child"
    sleep 2
  done
}

exec 3< <(events)
producer=$!
trap 'kill "$producer" 2>/dev/null' EXIT
# PIPE too: the bar's end of stdout closing is the usual way this learns it
# is not wanted, and dying of the signal would skip the EXIT trap above. A
# trapped (not ignored) signal is reset for children, so pw-mon still dies
# of it as it should.
trap 'exit 0' TERM INT HUP PIPE

read -r mic screen <<<"$(pw_state)"
rec=$(recording)
last=$(line "$mic" "$screen" "$rec")
printf '%s\n' "$last"

# pw-mon's objects: a header (`added:` / `changed:` / `removed:`), then the
# object's `id:`, then — except for removals — its `type:`. Nodes are
# remembered by id, because a removal names only the id, and most removals
# are not nodes: every pw-dump below is a client that comes and goes, and
# counting those would have each dump set off the next one, forever.
declare -A nodes=()
hdr="" id=""
dirty=0 settle=0 tick=$(( ${EPOCHREALTIME/./} + 5000000 ))

relevant() {  # $1 = one pw-mon line; true if the graph's answer may have moved
  case "$1" in
    added:|changed:|removed:) hdr=${1%:}; id=""; return 1 ;;
  esac
  [ -n "$hdr" ] || return 1
  if [ -z "$id" ]; then
    [[ $1 =~ ^[[:space:]]+id:\ ([0-9]+) ]] || return 1
    id=${BASH_REMATCH[1]}
    [ "$hdr" = removed ] || return 1
    hdr=""
    [ -n "${nodes[$id]:-}" ] || return 1
    unset "nodes[$id]"
    return 0
  fi
  case "$1" in
    *"type: PipeWire:Interface:Node"*) hdr=""; nodes[$id]=1; return 0 ;;
    *"type: "*) hdr=""; return 1 ;;
  esac
  return 1
}

while :; do
  # nobody left to read this: the shell that started it is gone
  ppid_of "$main"; [ "$ppid" = "$parent" ] || exit 0

  # Waiting on a change to settle, give it 0.2s of quiet; otherwise wait for
  # the next tick.
  t=${EPOCHREALTIME/./}
  if [ "$dirty" = 1 ]; then wait_us=200000; else wait_us=$(( tick - t )); fi
  [ "$wait_us" -gt 0 ] || wait_us=1
  printf -v wait_s '%d.%06d' $((wait_us / 1000000)) $((wait_us % 1000000))
  if IFS= read -r -t "$wait_s" -u 3 ev; then
    # A change arrives as a burst of objects; take the dump once it settles,
    # but never wait more than a second for a graph that will not. Every
    # line is still parsed while waiting, so no node's id is missed.
    if relevant "$ev" && [ "$dirty" = 0 ]; then
      dirty=1; settle=$(( ${EPOCHREALTIME/./} + 1000000 ))
    fi
    t=${EPOCHREALTIME/./}
    if [ "$dirty" = 1 ]; then [ "$t" -ge "$settle" ] || continue
    else [ "$t" -ge "$tick" ] || continue
    fi
  else
    # timed out: settled, or the tick. read's status is >128 on a timeout;
    # anything else is the producer gone, which only happens on the way out.
    [ $? -gt 128 ] || exit 0
  fi

  if [ "$dirty" = 1 ]; then
    read -r mic screen <<<"$(pw_state)"
    dirty=0
  fi
  if [ "${EPOCHREALTIME/./}" -ge "$tick" ]; then
    rec=$(recording)
    tick=$(( ${EPOCHREALTIME/./} + 5000000 ))
  fi
  cur=$(line "$mic" "$screen" "$rec")
  if [ "$cur" != "$last" ]; then
    printf '%s\n' "$cur" || exit 0
    last=$cur
  fi
done
