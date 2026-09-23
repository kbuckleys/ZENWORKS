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
parent=$PPID

# pw-mon, restarted if pipewire goes away and comes back. -o/-a keep it from
# printing every property of every node on every change; a pw-mon too old to
# know them falls back to the full output. Without pw-mon at all this still
# runs, as the five-second tick alone.
events() {
  command -v pw-mon >/dev/null 2>&1 || exec sleep infinity
  local child opts=(-N)
  pw-mon --help 2>&1 | grep -q -- --hide-params && opts=(-N -o -a)
  trap 'kill "$child" 2>/dev/null; exit 0' TERM INT
  while :; do
    pw-mon "${opts[@]}" 2>/dev/null &
    child=$!
    wait "$child"
    sleep 2
  done
}

exec 3< <(events)
producer=$!
trap 'kill "$producer" 2>/dev/null' EXIT
trap 'exit 0' TERM INT HUP

read -r mic screen <<<"$(pw_state)"
rec=$(recording)
last=$(line "$mic" "$screen" "$rec")
printf '%s\n' "$last"

hdr=""
while :; do
  pw=0
  if IFS= read -r -t 5 -u 3 ev; then
    # A node is announced as `added:` or `changed:` followed by its type a
    # few lines later; removals carry no type, so any removal counts.
    case "$ev" in
      added:|changed:) hdr=1; continue ;;
      removed:) pw=1 ;;
      *"type: PipeWire:Interface:Node"*) [ -n "$hdr" ] && pw=1; hdr="" ;;
      *"type: "*) hdr=""; continue ;;
      *) continue ;;
    esac
    # A change arrives as a burst of objects; take the dump once it settles,
    # but never wait more than a second for a graph that will not.
    deadline=$(( ${EPOCHREALTIME/./} + 1000000 ))
    while [ "${EPOCHREALTIME/./}" -lt "$deadline" ] \
          && IFS= read -r -t 0.2 -u 3 _; do :; done
  else
    # timed out: the tick. read's status is >128 on a timeout; anything else
    # is the producer gone, which only happens on the way out.
    [ $? -gt 128 ] || exit 0
    # nobody left to read this: the shell that started it is gone
    kill -0 "$parent" 2>/dev/null || exit 0
  fi

  [ "$pw" = 1 ] && read -r mic screen <<<"$(pw_state)"
  rec=$(recording)
  cur=$(line "$mic" "$screen" "$rec")
  if [ "$cur" != "$last" ]; then
    printf '%s\n' "$cur" || exit 0
    last=$cur
  fi
done
