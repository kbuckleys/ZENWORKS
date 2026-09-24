#!/usr/bin/env bash
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/

n() { local v="$1"; case "$v" in ""|"N/A"|"[N/A]") echo -n "" ;; *) echo -n "$v" ;; esac; }
trim() { printf '%s' "$1" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }
int() { local v="$(trim "$(n "$1")")"; case "$v" in ""|*[!0-9]*) echo -n "" ;; *) echo -n "$v" ;; esac; }
watt() { local v="$(trim "$(n "$1")")"; [ -z "$v" ] && { echo -n ""; return; }; awk -v x="$v" 'BEGIN { printf "%d", x }' 2>/dev/null; }

# Which card to report on. The one whose load can actually be read comes
# first: NVIDIA through nvidia-smi, then anything exposing gpu_busy_percent
# (amdgpu). Only then the card driving the display — on a hybrid laptop that
# is usually the Intel iGPU, which cannot say how busy it is (see below).
# cardN-<connector> entries are outputs, not cards, and are skipped.
cards=()
for d in /sys/class/drm/card*; do
  case "${d##*/}" in *-*) continue ;; esac
  [ -e "$d/device/vendor" ] && cards+=("$d")
done
card=""
if command -v nvidia-smi >/dev/null 2>&1; then
  for d in "${cards[@]}"; do
    [ "$(cat "$d/device/vendor")" = "0x10de" ] && { card="$d"; break; }
  done
fi
[ -z "$card" ] && for d in "${cards[@]}"; do
  [ -r "$d/device/gpu_busy_percent" ] && { card="$d"; break; }
done
[ -z "$card" ] && for d in "${cards[@]}"; do
  [ "$(cat "$d/device/boot_vga" 2>/dev/null)" = "1" ] && { card="$d"; break; }
done
[ -z "$card" ] && [ ${#cards[@]} -gt 0 ] && card="${cards[0]}"

if [ -z "$card" ]; then
  printf '{"present":false,"util":0,"temp":0,"tooltip":""}\n'
  exit 0
fi

vendor="$(cat "$card/device/vendor" 2>/dev/null)"

if [ "$vendor" = "0x10de" ]; then

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    printf '{"present":false,"util":0,"temp":0,"tooltip":""}\n'
    exit 0
  fi

  line=$(nvidia-smi --query-gpu=name,driver_version,utilization.gpu,temperature.gpu,power.draw,power.limit,memory.used,memory.total,fan.speed,pcie.link.gen.current,pcie.link.width.current \
    --format=csv,noheader,nounits 2>/dev/null | head -n1)
  IFS=',' read -r -a a <<< "$line"
  name="$(trim "${a[0]}")"
  driver="$(trim "${a[1]}")"
  util="$(int "${a[2]}")"
  temp="$(int "${a[3]}")"
  pdraw="$(watt "${a[4]}")"
  plimit="$(watt "${a[5]}")"
  memused="$(int "${a[6]}")"
  memtotal="$(int "${a[7]}")"
  fan="$(int "${a[8]}")"
  pciegen="$(trim "${a[9]}")"
  pciewidth="$(trim "${a[10]}")"

  util=${util:-0}
  temp=${temp:-0}

  tooltip="GPU: $name\nVendor: NVIDIA\nDriver: $driver\nUtilization: ${util}%\nTemperature: ${temp}°C"
  [ -n "$memtotal" ] && tooltip="$tooltip\nVRAM Used: ${memused:-0} MiB / ${memtotal} MiB"
  [ -n "$pdraw" ] && {
    if [ -n "$plimit" ]; then tooltip="$tooltip\nPower: ${pdraw}W / ${plimit}W"; else tooltip="$tooltip\nPower: ${pdraw}W"; fi
  }
  [ -n "$fan" ] && [ "$fan" -gt 0 ] && tooltip="$tooltip\nFan: ${fan}%"
  [ -n "$pciegen" ] && tooltip="$tooltip\nPCIe: ${pciegen} ${pciewidth}"


elif [ "$vendor" = "0x1002" ] || [ "$vendor" = "0x8086" ]; then

  device="$card/device"
  [ "$vendor" = "0x1002" ] && vname="AMD" || vname="Intel"

  # gpu_busy_percent is amdgpu's. Intel's i915 and xe drivers publish no load
  # figure an unprivileged process can read (intel_gpu_top needs perf access),
  # so there the load is UNKNOWN, reported as null, and shown as n/a rather
  # than as a meter sitting at a confident 0%.
  util="$(int "$(cat "$device/gpu_busy_percent" 2>/dev/null)")"

  hwmon="$(ls "$device/hwmon/" 2>/dev/null | head -n1)"
  if [ -n "$hwmon" ]; then
    temp="$(cat "$device/hwmon/$hwmon/temp1_input" 2>/dev/null)"
    temp=$((temp / 1000))
  else
    temp=""
  fi
  temp=${temp:-0}

  memused="$(cat "$device/mem_info_vram_used" 2>/dev/null)"
  memtotal="$(cat "$device/mem_info_vram_total" 2>/dev/null)"
  if [ -n "$memused" ] && [ -n "$memtotal" ] && [ "$memtotal" -gt 0 ]; then
    memused=$((memused / 1048576))
    memtotal=$((memtotal / 1048576))
  else
    memused=""
    memtotal=""
  fi

  pavg=""
  [ -n "$hwmon" ] && pavg="$(cat "$device/hwmon/$hwmon/power1_average" 2>/dev/null)"
  [ -n "$pavg" ] && pdraw="$(awk -v x="$pavg" 'BEGIN { printf "%d", x / 1000000 }' 2>/dev/null)" || pdraw=""

  bdf="$(basename "$(readlink "$device" 2>/dev/null)" 2>/dev/null)"
  slot="${bdf#0000:}"
  name="$(lspci -s "$slot" 2>/dev/null | sed -E 's/^[0-9a-fA-F:.]+ [^:]+: //; s/ \[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]//; s/ \(rev [0-9a-fA-F]+\)$//' | tr -s ' ')"
  [ -z "$name" ] && name="$vname GPU"

  if [ -n "$util" ]; then
    tooltip="GPU: $name\nVendor: $vname\nUtilization: ${util}%"
  else
    tooltip="GPU: $name\nVendor: $vname\nUtilization: n/a ($vname exposes no load without root)"
  fi
  [ -n "$temp" ] && [ "$temp" -gt 0 ] && tooltip="$tooltip\nTemperature: ${temp}°C"
  [ -n "$memtotal" ] && tooltip="$tooltip\nVRAM Used: ${memused} MiB / ${memtotal} MiB"
  [ -n "$pdraw" ] && tooltip="$tooltip\nPower: ${pdraw}W"

else
  printf '{"present":false,"util":0,"temp":0,"tooltip":""}\n'
  exit 0
fi

tooltip="$(printf '%b' "$tooltip")"

# No `text` field: the label and the meter are built in GpuModule.qml, so the
# palette lives in Zenon alone rather than being restated as hex in here.
# util is null when the driver cannot say (Intel); a number otherwise.
jq -nc --arg util "${util:-}" --argjson temp "${temp:-0}" --arg tooltip "$tooltip" \
  '{present: true, util: (if $util == "" then null else ($util | tonumber) end),
    temp: $temp, tooltip: $tooltip}'
