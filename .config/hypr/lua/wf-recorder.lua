-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

local function record(mode)
	-- The videos directory from user-dirs.dirs; see hyprshot.lua for the
	-- $HOME fallback.
	local script = [[
vids=$(xdg-user-dir VIDEOS 2>/dev/null || true)
{ [ -n "$vids" ] && [ "$vids" != "$HOME" ]; } || vids="$HOME/Videos"
output_dir="$vids/Captures"
mkdir -p "$output_dir"

if pgrep -x wf-recorder >/dev/null; then
  pkill -SIGINT -x wf-recorder
  # wait for it to finalize the file before notifying
  for _ in 1 2 3 4 5; do
    pgrep -x wf-recorder >/dev/null || break
    sleep 0.2
  done
  file=$(cat "$output_dir/.active-recording" 2>/dev/null)
  if [ -n "$file" ] && [ -f "$file" ]; then
    notify-send -u low "󰕧 Recording Stopped" "$file"
  else
    notify-send "󰕧 Recording Stopped"
  fi
  rm -f "$output_dir/.active-recording"
  exit 0
fi

monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1)
[ -n "$monitor" ] || { notify-send "󱠑 No monitor"; exit 1; }

filename="$output_dir/$(date +'%Y-%m-%d-%H%M%S')-$monitor.mp4"
log=$(mktemp)

# -D (continuous capture) is REQUIRED: with the default damage-based capture a
# static screen delivers too few frames, and a race in wf-recorder's audio/video
# sync drops them all, leaving an audio-only file.
base=(-D -r 60)

# An empty --audio= aborts inside libpulse and leaves a truncated file behind,
# so only ask for audio once a monitor source is actually known to exist
audio=$(pactl list short sources 2>/dev/null | awk '$2 ~ /\.monitor$/ {print $2; exit}')
[ -n "$audio" ] && base+=(--audio="$audio")

case "${1}" in
  full)
    target=(-o "$monitor")
    label="󰑋 Full Screen"; detail="$monitor"
    ;;
  region)
    geometry=$(slurp -d) || exit 0
    [ -n "$geometry" ] || exit 0
    target=(-g "$geometry")
    label=" Region Recording"; detail=""
    ;;
  window)
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
    exit 0
  fi
  # a failed start can leave a stub behind, and wf-recorder asks before
  # overwriting a file, which would hang the next attempt
  rm -f "$filename"
done

notify-send -u critical " Recording failed" "$(tail -n 3 "$log")"
rm -f "$log"
exit 1
]]
	hl.exec_cmd("bash -c '" .. script:gsub("'", "'\"'\"'") .. "' -- " .. mode)
end

-- BINDS
hl.bind("SUPER + R",            function() record("full") end)
hl.bind("SUPER + SHIFT + R",    function() record("window") end)
hl.bind("SUPER + CONTROL + R",  function() record("region") end)
