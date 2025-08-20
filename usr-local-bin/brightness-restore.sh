#!/usr/bin/env bash
# restores amd backlight brightness at boot from a saved state or a ~50% default

set -euo pipefail

STATE_DIR="/var/lib/backlight"

AMD_BL=$(ls /sys/class/backlight 2>/dev/null | grep -E '^amdgpu_bl[0-9]+' | head -n1 || true)
[[ -z "$AMD_BL" ]] && exit 0

BR="/sys/class/backlight/$AMD_BL/brightness"
MAX="/sys/class/backlight/$AMD_BL/max_brightness"
SAVE_FILE="$STATE_DIR/$AMD_BL.value"

if [[ -r "$SAVE_FILE" ]]; then
  VAL=$(cat "$SAVE_FILE")
else
  if [[ -r "$MAX" ]]; then
    MAXV=$(cat "$MAX"); [[ "$MAXV" =~ ^[0-9]+$ ]] || MAXV=255
    VAL=$(( MAXV / 2 )); (( VAL < 1 )) && VAL=1
  else
    VAL=128
  fi
fi

if [[ -r "$MAX" ]]; then
  MAXV=$(cat "$MAX"); [[ "$MAXV" =~ ^[0-9]+$ ]] || MAXV=255
  (( VAL < 1 )) && VAL=1
  (( VAL > MAXV )) && VAL=$MAXV
fi

echo "$VAL" > "$BR" || true

