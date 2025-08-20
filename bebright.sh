#!/usr/bin/env bash
# copies separate files into place, sets GRUB arg, fills templates with the detected device,
# and enables systemd units. use --revert to undo. no Xorg involved.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RESTORE_BIN_SRC="$ROOT_DIR/usr-local-bin/brightness-restore.sh"
SAVE_BIN_SRC="$ROOT_DIR/usr-local-bin/brightness-save.sh"

UDEV_TMPL="$ROOT_DIR/etc-udev-rules.d/99-backlight.rules.tmpl"

RESTORE_UNIT_SRC="$ROOT_DIR/etc-systemd-system/brightness-restore.service"
SAVE_UNIT_SRC="$ROOT_DIR/etc-systemd-system/brightness-save@.service"
SAVE_PATH_SRC="$ROOT_DIR/etc-systemd-system/brightness-save@.path"

RESTORE_BIN_DST="/usr/local/bin/brightness-restore.sh"
SAVE_BIN_DST="/usr/local/bin/brightness-save.sh"

UDEV_DST="/etc/udev/rules.d/99-backlight.rules"

RESTORE_UNIT_DST="/etc/systemd/system/brightness-restore.service"
SAVE_UNIT_DST="/etc/systemd/system/brightness-save@.service"
SAVE_PATH_DST="/etc/systemd/system/brightness-save@.path"

GRUB_CFG="/etc/default/grub"

revert=false
[[ "${1:-}" == "--revert" ]] && revert=true

require_root() {
  [[ $EUID -eq 0 ]] || { echo "run as root: sudo bash $0"; exit 1; }
}

detect_amdgpu_bl() {
  ls /sys/class/backlight 2>/dev/null | grep -E '^amdgpu_bl[0-9]+' | head -n1 || true
}

set_grub_arg() {
  if [[ -f "$GRUB_CFG" ]]; then
    if ! grep -q 'acpi_backlight=vendor' "$GRUB_CFG"; then
      sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 acpi_backlight=vendor"/' "$GRUB_CFG"
      grub-mkconfig -o /boot/grub/grub.cfg
      echo "added kernel arg: acpi_backlight=vendor (reboot to apply)"
    else
      echo "GRUB already has acpi_backlight=vendor"
    fi
  else
    echo "warning: $GRUB_CFG not found; skipping GRUB change"
  fi
}

unset_grub_arg() {
  if [[ -f "$GRUB_CFG" ]] && grep -q 'acpi_backlight=vendor' "$GRUB_CFG"; then
    sed -i 's/ acpi_backlight=vendor//g' "$GRUB_CFG"
    grub-mkconfig -o /boot/grub/grub.cfg
    echo "removed kernel arg: acpi_backlight=vendor"
  fi
}

install_files() {
  local dev="$1"

  # copy scripts
  install -m 0755 -D "$RESTORE_BIN_SRC" "$RESTORE_BIN_DST"
  install -m 0755 -D "$SAVE_BIN_SRC"    "$SAVE_BIN_DST"
  mkdir -p /var/lib/backlight && chmod 755 /var/lib/backlight

  # render udev template with device name
  sed "s/__AMD_BL__/$dev/g" "$UDEV_TMPL" > "$UDEV_DST"

  # copy units
  install -m 0644 -D "$RESTORE_UNIT_SRC" "$RESTORE_UNIT_DST"
  install -m 0644 -D "$SAVE_UNIT_SRC"    "$SAVE_UNIT_DST"
  install -m 0644 -D "$SAVE_PATH_SRC"    "$SAVE_PATH_DST"

  # reload services and udev
  systemctl daemon-reload
  udevadm control --reload
  udevadm trigger --subsystem-match=backlight || true

  # enable
  systemctl enable --now brightness-restore.service
  systemctl enable --now "brightness-save@${dev}.path"

  echo "installed and enabled units for device: $dev"
}

remove_files() {
  # disable units (try common instances)
  systemctl disable --now "brightness-save@amdgpu_bl0.path" 2>/dev/null || true
  systemctl disable --now "brightness-save@amdgpu_bl1.path" 2>/dev/null || true
  systemctl disable --now "brightness-save@amdgpu_bl2.path" 2>/dev/null || true
  systemctl disable --now brightness-restore.service 2>/dev/null || true

  # remove units
  rm -f "$RESTORE_UNIT_DST" "$SAVE_UNIT_DST" "$SAVE_PATH_DST"
  systemctl daemon-reload

  # remove udev rule
  rm -f "$UDEV_DST"
  udevadm control --reload
  udevadm trigger --subsystem-match=backlight || true

  echo "removed units and udev rule"
}

bump_if_dim() {
  local dev="$1" br max mid cur
  br="/sys/class/backlight/$dev/brightness"
  max="/sys/class/backlight/$dev/max_brightness"
  [[ -w "$br" && -r "$max" ]] || return 0
  max=$(cat "$max"); [[ "$max" =~ ^[0-9]+$ ]] || max=255
  mid=$(( max / 2 )); (( mid < 1 )) && mid=1
  cur=$(cat "$br")
  (( cur < mid )) && echo "$mid" > "$br" || true
}

# main
require_root

if $revert; then
  echo "[revert] removing installed files and GRUB arg…"
  remove_files
  unset_grub_arg
  echo "revert complete. reboot recommended."
  exit 0
fi

AMD_BL=$(detect_amdgpu_bl)
if [[ -z "$AMD_BL" ]]; then
  echo "no amdgpu_bl* visible yet; will assume amdgpu_bl2 for now"
  AMD_BL="amdgpu_bl2"
fi
echo "using device: $AMD_BL"

set_grub_arg
install_files "$AMD_BL"
bump_if_dim "$AMD_BL"

echo
echo "Done."

