#!/usr/bin/env bash
set -u
IFS=$'\n\t'

PACKAGE_NAME="aoc-i1659fwux-rpi-displaylink"
STATE_DIR="/var/lib/${PACKAGE_NAME}"
SAFE_UNIT="aoc-i1659fwux-displaylink.service"
AOC_USB_ID="17e9:ff10"
RUNTIME_DIR="/run/aoc-i1659fwux-displaylink"

section() {
  printf '\n== %s ==\n' "$1"
}

read_pi_model() {
  if [[ -r /proc/device-tree/model ]]; then
    tr -d '\0' < /proc/device-tree/model
  else
    printf 'unknown'
  fi
}

session_value() {
  loginctl show-session "$1" --property="$2" --value 2>/dev/null || true
}

section "Platform"
printf 'Model: %s\n' "$(read_pi_model)"
printf 'Architecture: %s\n' "$(uname -m)"
printf 'Kernel: %s\n' "$(uname -r)"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  printf 'OS: %s\n' "${PRETTY_NAME:-unknown}"
fi

section "AOC USB monitor"
if command -v lsusb >/dev/null 2>&1 && lsusb -d "${AOC_USB_ID}" 2>/dev/null; then
  lsusb -t 2>/dev/null | sed 's/^/USB tree: /' || true
else
  echo "Not detected (${AOC_USB_ID})."
fi

section "EVDI"
if command -v lsmod >/dev/null 2>&1 && lsmod 2>/dev/null | awk '{print $1}' | grep -qx evdi; then
  echo "Kernel module: loaded"
else
  echo "Kernel module: not loaded"
fi
if [[ -r /sys/devices/evdi/version ]]; then
  printf 'Loaded version: %s\n' "$(cat /sys/devices/evdi/version)"
fi
if command -v modinfo >/dev/null 2>&1; then
  printf 'Module file: %s\n' "$(modinfo -n evdi 2>/dev/null || echo not-found)"
fi
if command -v dkms >/dev/null 2>&1; then
  dkms status 2>/dev/null | grep '^evdi/' || echo "DKMS: no EVDI registration found"
fi

section "Post-login DisplayLink broker"
systemctl status "${SAFE_UNIT}" --no-pager 2>/dev/null || true
if [[ -r "${RUNTIME_DIR}/broker.state" ]]; then
  echo "Broker state:"
  sed 's/^/  /' "${RUNTIME_DIR}/broker.state"
else
  echo "Broker state file: not present"
fi
if [[ -e "${RUNTIME_DIR}/blocked-this-boot" ]]; then
  echo "Safety block: active for this boot"
  sed 's/^/  /' "${RUNTIME_DIR}/blocked-this-boot" 2>/dev/null || true
else
  echo "Safety block: not active"
fi
if pgrep -f '/opt/displaylink/DisplayLinkManager' >/dev/null 2>&1; then
  echo "DisplayLinkManager: running"
else
  echo "DisplayLinkManager: not running"
fi

section "Login sessions"
if command -v loginctl >/dev/null 2>&1; then
  loginctl list-sessions --no-legend 2>/dev/null || true
  while IFS= read -r sid; do
    [[ -n "$sid" ]] || continue
    printf '%s: user=%s uid=%s class=%s type=%s active=%s state=%s remote=%s\n' \
      "$sid" \
      "$(session_value "$sid" Name)" \
      "$(session_value "$sid" User)" \
      "$(session_value "$sid" Class)" \
      "$(session_value "$sid" Type)" \
      "$(session_value "$sid" Active)" \
      "$(session_value "$sid" State)" \
      "$(session_value "$sid" Remote)"
  done < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}')
else
  echo "loginctl is unavailable."
fi

section "Graphical session processes"
for process in labwc wayfire Xorg Xwayland weston sway gnome-shell kwin_wayland; do
  if pgrep -x "$process" >/dev/null 2>&1; then
    printf 'Running: %s\n' "$process"
  fi
done

section "DRM connectors"
found=0
for connector in /sys/class/drm/card*-*; do
  [[ -e "$connector" ]] || continue
  connector_base="$(basename -- "$connector")"
  card_name="${connector_base%%-*}"
  card="/sys/class/drm/${card_name}"
  driver="$(basename "$(readlink -f "${card}/device/driver" 2>/dev/null)" 2>/dev/null || true)"
  [[ "$driver" == "evdi" ]] || continue
  found=1
  printf '%s: %s\n' "$connector_base" "$(cat "${connector}/status" 2>/dev/null || echo unknown)"
  if [[ -s "${connector}/modes" ]]; then
    sed 's/^/  mode: /' "${connector}/modes"
  fi
done
(( found == 1 )) || echo "No EVDI connector is currently visible."

section "Native-mode check"
native=0
for modes in /sys/class/drm/card*-*/modes; do
  [[ -f "$modes" ]] || continue
  connector="${modes%/*}"
  connector_base="$(basename -- "$connector")"
  card_name="${connector_base%%-*}"
  card="/sys/class/drm/${card_name}"
  driver="$(basename "$(readlink -f "${card}/device/driver" 2>/dev/null)" 2>/dev/null || true)"
  [[ "$driver" == "evdi" ]] || continue
  grep -qx '1920x1080' "$modes" && native=1
done
if (( native == 1 )); then
  echo "1920x1080 is exposed."
else
  echo "1920x1080 is not currently exposed by an EVDI connector."
fi

section "User-space binary"
if [[ -x /opt/displaylink/DisplayLinkManager ]]; then
  command -v file >/dev/null 2>&1 && file /opt/displaylink/DisplayLinkManager 2>/dev/null || true
  if readelf -l /opt/displaylink/DisplayLinkManager 2>/dev/null | grep -q INTERP; then
    LD_LIBRARY_PATH=/opt/displaylink ldd /opt/displaylink/DisplayLinkManager 2>/dev/null || true
  fi
else
  echo "DisplayLinkManager is not installed at /opt/displaylink."
fi

section "Installation state"
if [[ -r "${STATE_DIR}/install-info" ]]; then
  cat "${STATE_DIR}/install-info"
else
  echo "No installation state found."
fi

section "Recent broker log"
journalctl -u "${SAFE_UNIT}" -n 60 --no-pager 2>/dev/null || true
