#!/usr/bin/env bash
# saves current amd backlight brightness so it can be restored on next boot

set -euo pipefail

STATE_DIR="/var/lib/backlight"
mkdir -p "$STATE_DIR"

for dev in /sys/class/backlight/amdgpu_bl*; do
  [[ -e "$dev/brightness" ]] || continue
  VAL=$(cat "$dev/brightness" 2>/dev/null || echo "")
  [[ -n "$VAL" ]] || continue
  echo "$VAL" > "$STATE_DIR/$(basename "$dev").value"
done

