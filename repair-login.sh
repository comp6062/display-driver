#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 022

PACKAGE_NAME="aoc-i1659fwux-rpi-displaylink"
STATE_DIR="/var/lib/${PACKAGE_NAME}"
INSTALL_ROOT="/opt/displaylink"
SAFE_UNIT="aoc-i1659fwux-displaylink.service"
SAFE_UNIT_PATH="/etc/systemd/system/${SAFE_UNIT}"
UDEV_RULE_PATH="/etc/udev/rules.d/99-aoc-i1659fwux-displaylink.rules"
AUTOSTART_PATH="/etc/xdg/autostart/aoc-i1659fwux-displaylink.desktop"
MODULE_LOAD_PATH="/etc/modules-load.d/aoc-i1659fwux-evdi.conf"
EVDI_MODPROBE_PATH="/etc/modprobe.d/evdi.conf"
RUNTIME_DIR="/run/aoc-i1659fwux-displaylink"

log() {
  printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"
}

warn() {
  log "WARNING: $*" >&2
}

[[ ${EUID} -eq 0 ]] || {
  log "ERROR: Run this repair through sudo." >&2
  exit 1
}

log "Stopping the AOC driver before it can participate in another LightDM login attempt."
systemctl disable --now "${SAFE_UNIT}" >/dev/null 2>&1 || true
pkill -TERM -f '^/opt/displaylink/DisplayLinkManager$' >/dev/null 2>&1 || true
sleep 1
pkill -KILL -f '^/opt/displaylink/DisplayLinkManager$' >/dev/null 2>&1 || true
rm -f -- "${SAFE_UNIT_PATH}" \
  "/etc/systemd/system/graphical.target.wants/${SAFE_UNIT}" \
  "${AUTOSTART_PATH}" "${MODULE_LOAD_PATH}" "${UDEV_RULE_PATH}"
rm -rf -- "${RUNTIME_DIR}"
systemctl daemon-reload >/dev/null 2>&1 || true

state_file="${STATE_DIR}/evdi-config/evdi.conf.state"
backup_file="${STATE_DIR}/evdi-config/evdi.conf.before"
if [[ -f "$state_file" ]] && grep -qx 'present' "$state_file" \
    && [[ -e "$backup_file" || -L "$backup_file" ]]; then
  rm -f -- "${EVDI_MODPROBE_PATH}"
  cp -a -- "$backup_file" "${EVDI_MODPROBE_PATH}"
elif [[ -f "$state_file" ]] && grep -qx 'absent' "$state_file"; then
  rm -f -- "${EVDI_MODPROBE_PATH}"
elif [[ -f "${EVDI_MODPROBE_PATH}" ]] \
    && grep -Fq 'AOC I1659FWUX' "${EVDI_MODPROBE_PATH}" \
    && grep -Fq 'initial_device_count=1' "${EVDI_MODPROBE_PATH}"; then
  rm -f -- "${EVDI_MODPROBE_PATH}"
fi

modprobe -r evdi >/dev/null 2>&1 || true

version=""
if [[ -r "${STATE_DIR}/evdi-version" ]]; then
  version="$(cat "${STATE_DIR}/evdi-version")"
fi
if [[ -n "$version" && "$version" =~ ^[0-9][0-9A-Za-z.+~-]*$ ]] \
    && command -v dkms >/dev/null 2>&1; then
  if dkms remove -m evdi -v "$version" --all >/dev/null 2>&1; then
    rm -rf -- "/usr/src/evdi-${version}"
  else
    warn "EVDI DKMS removal did not complete. The reboot will still remove the active in-memory device."
  fi
fi

rm -rf -- "${INSTALL_ROOT}"
udevadm control --reload-rules >/dev/null 2>&1 || true
depmod -a >/dev/null 2>&1 || true
systemctl daemon-reload >/dev/null 2>&1 || true

if [[ -d "${STATE_DIR}" ]]; then
  backup_dir="/var/backups/${PACKAGE_NAME}-login-repair-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$(dirname -- "$backup_dir")"
  mv -- "${STATE_DIR}" "$backup_dir"
  log "Previous driver diagnostics were preserved at ${backup_dir}."
fi

log "The pre-login DisplayLink service and EVDI preload have been removed."
log "No password, PAM, user, autologin, LightDM, SSH, or boot-target setting was changed."
log "Reboot now. The original desktop/autologin path should return after the reboot."
