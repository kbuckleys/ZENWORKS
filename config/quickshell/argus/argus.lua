-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- ARGUS — the recorder. The hundred-eyed watchman: it keeps an eye on the
-- screen while you work. Moved here from hypr/lua/wf-recorder.lua (10-20) so
-- the video capture lives with the rest of the shell; hyprland.lua loads it
-- from here, and its binds are in hypr/lua/binds.lua under CAPTURE, where
-- oracle's Shortcuts lists them.

local function record(mode)
	-- The videos directory from user-dirs.dirs. xdg-user-dir answers $HOME
	-- itself when nothing is configured, which is not somewhere to drop
	-- recordings, so that falls back to ~/Videos.
	local script = [[
vids=$(xdg-user-dir VIDEOS 2>/dev/null || true)
{ [ -n "$vids" ] && [ "$vids" != "$HOME" ]; } || vids="$HOME/Videos"
output_dir="$vids/Captures"
mkdir -p "$output_dir"

# The sound mixed for "Both" (below) is a null sink and two loopbacks,
# loaded for the one recording; their ids are kept here and unloaded after.
unmix() {
  for m in $(cat "$output_dir/.active-modules" 2>/dev/null); do pactl unload-module "$m" 2>/dev/null; done
  rm -f "$output_dir/.active-modules"
}

if pgrep -x wf-recorder >/dev/null; then
  pkill -SIGINT -x wf-recorder
  # wait for it to finalize the file before notifying
  for _ in 1 2 3 4 5; do
    pgrep -x wf-recorder >/dev/null || break
    sleep 0.2
  done
  file=$(cat "$output_dir/.active-recording" 2>/dev/null)
  if [ -n "$file" ] && [ -f "$file" ]; then
    # howler's capture card: a frame of the recording, with the hints that
    # say what it is a frame of. A recording too short to seek a second
    # into gives its first frame instead; no frame at all is a plain toast.
    thumb="${XDG_RUNTIME_DIR:-/tmp}/howler-capture-$(basename "$file" .mp4).png"
    # (ffmpeg seeking past the end still exits 0, having written nothing,
    # so the fallback goes by whether the file is there, not by the status)
    rm -f "$thumb"
    ffmpeg -nostdin -loglevel quiet -y -ss 1 -i "$file" -frames:v 1 "$thumb"
    [ -s "$thumb" ] || ffmpeg -nostdin -loglevel quiet -y -i "$file" -frames:v 1 "$thumb"
    if [ -s "$thumb" ]; then
      notify-send -i "$thumb" -h string:x-howler-capture:video -h "string:x-howler-file:$file" \
        -h "string:x-howler-picture:$thumb" \
        "󰕧 Recording Stopped" "$file"
    else
      notify-send -u low "󰕧 Recording Stopped" "$file"
    fi
  else
    notify-send "󰕧 Recording Stopped"
  fi
  rm -f "$output_dir/.active-recording"
  unmix
  qs ipc call Argus recording false >/dev/null 2>&1
  exit 0
fi
# "stop" with nothing recording does nothing — never starts one
[ "${1}" = stop ] && exit 0

monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1)
[ -n "$monitor" ] || { notify-send "󱠑 No monitor"; exit 1; }

filename="$output_dir/$(date +'%Y-%m-%d-%H%M%S')-$monitor.mp4"
log=$(mktemp)

# -D (continuous capture) is REQUIRED: with the default damage-based capture a
# static screen delivers too few frames, and a race in wf-recorder's audio/video
# sync drops them all, leaving an audio-only file.
base=(-D -r 60)

# ── WHAT ORACLE SAYS (2026-10-22) ───────────────────────────────────────
# `qs ipc call Argus recPrefs` answers one line of key=value words; a shell
# that is not running (or too old to know the call) answers nothing, and
# everything stays as it recorded before these existed.
countdown=0; audiomode=system
for kv in $(qs ipc call Argus recPrefs 2>/dev/null); do
  case "$kv" in
    countdown=[0-9]|countdown=10) countdown=${kv#*=} ;;
    audio=none|audio=system|audio=mic|audio=both) audiomode=${kv#*=} ;;
  esac
done

# An empty --audio= aborts inside libpulse and leaves a truncated file behind,
# so only ask for audio once a source is actually known to exist. What the
# machine plays is its default output's monitor (else the first monitor
# there is); the microphone is the default input, never a monitor.
sink=$(pactl get-default-sink 2>/dev/null)
system=""
[ -n "$sink" ] && pactl list short sources 2>/dev/null | awk '{print $2}' | grep -qx "$sink.monitor" && system="$sink.monitor"
[ -n "$system" ] || system=$(pactl list short sources 2>/dev/null | awk '$2 ~ /\.monitor$/ {print $2; exit}')
mic=$(pactl get-default-source 2>/dev/null)
case "$mic" in *.monitor) mic="" ;; esac
audio=""
case "$audiomode" in
  system) audio="$system" ;;
  mic) audio="$mic" ;;
  both)
    if [ -n "$system" ] && [ -n "$mic" ]; then
      # one source wf-recorder can take: a null sink both are looped into
      mods=$(pactl load-module module-null-sink sink_name=argus_mix sink_properties=device.description=Argus-mix)
      mods="$mods $(pactl load-module module-loopback source="$system" sink=argus_mix latency_msec=30)"
      mods="$mods $(pactl load-module module-loopback source="$mic" sink=argus_mix latency_msec=30)"
      echo "$mods" > "$output_dir/.active-modules"
      audio=argus_mix.monitor
    else
      audio="${system:-$mic}"
    fi
    ;;
esac
[ -n "$audio" ] && base+=(--audio="$audio")

# ── THE AREA, FROM PICASSO'S PICKER ─────────────────────────────────────
# Region recordings are picked in the region screenshot's own
# overlay (picasso/PicassoCapture.qml), not slurp: the box can be adjusted
# before it is taken, the presets and "the last region" are there, and a
# window is clicked, lit as the pointer crosses it. The ipc call answers at
# once — "picking" — and the rectangle comes later, written to $reply in
# slurp's own "X,Y WxH"; an empty file is Escape. Anything but "picking" is a
# shell that is not running, or one too old to know the call (reloaded
# without picasso's change), and that is the only time slurp is asked.
# The wait has a ceiling, and gives up the moment the shell is gone, so a
# shell that dies with the overlay up cannot leave this script behind.
pick() {
  reply="${XDG_RUNTIME_DIR:-/tmp}/argus-pick-$$"
  rm -f "$reply" "$reply.part"
  [ "$(qs ipc call Picasso "$1" "$reply" 2>/dev/null)" = picking ] || return 2
  for i in $(seq 6000); do
    [ -e "$reply" ] && break
    [ $((i % 10)) = 0 ] && ! pgrep -x qs >/dev/null && break
    sleep 0.1
  done
  geometry=$(cat "$reply" 2>/dev/null)
  rm -f "$reply"
  [ -n "$geometry" ] || return 1
  # the overlay goes the moment it answers; a beat more makes sure its last
  # frame is off the screen before the first one is recorded
  sleep 0.15
}

case "${1}" in
  full)
    target=(-o "$monitor")
    label="󰑋 Full Screen"; detail="$monitor"
    ;;
  region)
    pick pickRegion; r=$?
    [ "$r" = 1 ] && exit 0
    if [ "$r" = 2 ]; then
      geometry=$(slurp -d) || exit 0
      [ -n "$geometry" ] || exit 0
    fi
    target=(-g "$geometry")
    label=" Region Recording"; detail=""
    ;;
  window)
    # the window with the keyboard, at once — the way SUPER+PRINT takes a
    # window shot, no picker (10-21). Picasso's pickWindow is still there
    # for anything that wants to ask.
    geometry=$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
    # jq prints the literal "null,null nullxnull" when nothing is focused, which
    # is non-empty and would sail past a -n test into a wf-recorder parse error
    [ "$geometry" != "null,null nullxnull" ] || { notify-send " No window"; exit 1; }
    target=(-g "$geometry")
    label=" Window Recording"; detail=""
    ;;
  *)
    notify-send -u critical "󱠑 Unknown mode" "${1}"
    exit 1
    ;;
esac

# ── THE COUNTDOWN ───────────────────────────────────────────────────────
# Shown by the shell in the middle of the screen; waited out here, and a
# beat more so its last frame is gone before the first one is recorded.
if [ "$countdown" -gt 0 ] 2>/dev/null; then
  qs ipc call Argus countdown "$countdown" >/dev/null 2>&1 && sleep "$countdown" && sleep 0.3
fi

# ── THE ENCODER, FROM THE HARDWARE THAT IS THERE ────────────────────────
# NVENC on NVIDIA, VA-API on an AMD or Intel GPU's own render node (found by
# vendor, so a hybrid laptop does not guess at renderD128), and x264 in
# software as the floor that always exists. Each is tried in turn: whatever
# the driver setup, the first one that actually starts is the one used.
vendor() { cat "$1/device/vendor" 2>/dev/null; }
nvidia=0
for d in /sys/class/drm/card*; do
  case "${d##*/}" in *-*) continue ;; esac   # connectors, not cards
  [ "$(vendor "$d")" = 0x10de ] && nvidia=1
done
node=""
for r in /sys/class/drm/renderD*; do
  case "$(vendor "$r")" in 0x1002|0x8086) node="/dev/dri/${r##*/}"; break ;; esac
done
encoders=()
[ "$nvidia" = 1 ] && encoders+=(nvenc)
[ -n "$node" ] && encoders+=(vaapi)
encoders+=(x264)

encoder_args() {
  case "$1" in
    # h264_nvenc dropped the old named presets, so preset=lossless is rejected
    # by ffmpeg and the encoder never opens. High-quality VBR, not lossless;
    # that would be preset p7 + tune lossless.
    nvenc) enc=(-c h264_nvenc -p preset=p7 -p tune=hq -p rc=vbr -p cq=20 -p b:v=0) ;;
    vaapi) enc=(-c h264_vaapi -d "$node" -p qp=20) ;;
    x264)  enc=(-c libx264 -p preset=veryfast -p crf=20) ;;
  esac
}

# wf-recorder gives up within a moment when the codec or geometry is rejected,
# so a start is only believed once it is still running a second later.
for e in "${encoders[@]}"; do
  encoder_args "$e"
  wf-recorder "${base[@]}" "${enc[@]}" "${target[@]}" -f "$filename" >"$log" 2>&1 &
  pid=$!
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    rm -f "$log"
    echo "$filename" > "$output_dir/.active-recording"
    notify-send "$label" "${detail:+$detail · }$e"
    qs ipc call Argus recording true >/dev/null 2>&1
    exit 0
  fi
  # a failed start can leave a stub behind, and wf-recorder asks before
  # overwriting a file, which would hang the next attempt
  rm -f "$filename"
done

notify-send -u critical " Recording failed" "$(tail -n 3 "$log")"
rm -f "$log"
unmix
exit 1
]]
	hl.exec_cmd("bash -c '" .. script:gsub("'", "'\"'\"'") .. "' -- " .. mode)
end

-- The bar's recording dot stops a recording through this, so it says the
-- same "Recording Stopped" the binds do: `hyprctl repl 'ZenRecord("stop")'`.
ZenRecord = record
