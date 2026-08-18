#!/usr/bin/env bash

if ! command -v nvidia-smi >/dev/null 2>&1; then
  printf '{"text":"","tooltip":""}\n'
  exit 0
fi

read -r util temp memused memtotal < <(
  nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total \
    --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' | tr ',' ' '
)

util=${util:-0}
temp=${temp:-0}
memused=${memused:-0}
memtotal=${memtotal:-0}

tooltip=$(printf 'GPU Utilization: %s%%\nGPU Temperature: %s°C\nVRAM Used: %s MiB / %s MiB' \
  "$util" "$temp" "$memused" "$memtotal")

jq -nc \
  --arg text " <span foreground='#a2a8bc'>GPU</span> ${util}% ${temp}° " \
  --arg tooltip "$tooltip" \
  '{text: $text, tooltip: $tooltip}'
