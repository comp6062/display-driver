#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 022

PACKAGE_NAME="aoc-i1659fwux-rpi-displaylink"
STATE_DIR="/var/lib/${PACKAGE_NAME}"
LOG_DIR="/var/log/${PACKAGE_NAME}"
INSTALL_ROOT="/opt/displaylink"
SAFE_UNIT="aoc-i1659fwux-displaylink.service"
SAFE_UNIT_PATH="/etc/systemd/system/${SAFE_UNIT}"
UDEV_RULE_PATH="/etc/udev/rules.d/99-aoc-i1659fwux-displaylink.rules"
MODULE_LOAD_PATH="/etc/modules-load.d/aoc-i1659fwux-evdi.conf"
EVDI_MODPROBE_PATH="/etc/modprobe.d/evdi.conf"
KEEP_BACKUP=0

log() {
  printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"
}

warn() {
  log "WARNING: $*" >&2
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: sudo ./uninstall.sh [--keep-backup]

Removes this package's DisplayLink user-space files, post-login broker, exact
AOC udev rule, and EVDI DKMS registration. It restores any evdi.conf file that
existed before installation. Dependency packages are deliberately retained.
USAGE
}

restore_evdi_config() {
  rm -f -- "${MODULE_LOAD_PATH}"
  rm -f -- "${UDEV_RULE_PATH}"

  local state_file="${STATE_DIR}/evdi-config/evdi.conf.state"
  local backup="${STATE_DIR}/evdi-config/evdi.conf.before"
  if [[ -f "$state_file" ]] && grep -qx 'present' "$state_file" \
      && [[ -e "$backup" || -L "$backup" ]]; then
    rm -f -- "${EVDI_MODPROBE_PATH}"
    cp -a -- "$backup" "${EVDI_MODPROBE_PATH}"
  elif [[ -f "$state_file" ]] && grep -qx 'absent' "$state_file"; then
    rm -f -- "${EVDI_MODPROBE_PATH}"
  fi
}

remove_evdi() {
  local version=""
  if [[ -r "${STATE_DIR}/evdi-version" ]]; then
    version="$(cat "${STATE_DIR}/evdi-version")"
  fi

  modprobe -r evdi >/dev/null 2>&1 || true

  if [[ -n "$version" && "$version" =~ ^[0-9][0-9A-Za-z.+~-]*$ ]]; then
    if command -v dkms >/dev/null 2>&1; then
      if dkms remove -m evdi -v "$version" --all; then
        rm -rf -- "/usr/src/evdi-${version}"
      else
        warn "EVDI DKMS removal failed; preserving /usr/src/evdi-${version} for manual recovery."
      fi
    else
      warn "DKMS is unavailable; preserving /usr/src/evdi-${version} for manual recovery."
    fi
  else
    warn "The package's recorded EVDI version is unavailable."
    warn "No unrecorded EVDI DKMS registration will be removed automatically."
  fi
}

main() {
  while (($#)); do
    case "$1" in
      --keep-backup) KEEP_BACKUP=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done

  [[ ${EUID} -eq 0 ]] || die "Run this uninstaller with sudo."
  [[ -d "${STATE_DIR}" ]] || die "No ${PACKAGE_NAME} installation state was found."

  install -d -m 0750 "${LOG_DIR}"
  local log_file="${LOG_DIR}/uninstall-$(date +%Y%m%d-%H%M%S).log"
  touch "$log_file"
  chmod 0640 "$log_file"
  exec > >(tee -a "$log_file") 2>&1

  log "Stopping and removing the AOC post-login DisplayLink broker."
  systemctl disable --now "${SAFE_UNIT}" >/dev/null 2>&1 || true
  rm -f -- "${SAFE_UNIT_PATH}"
  systemctl daemon-reload

  remove_evdi
  rm -rf -- "${INSTALL_ROOT}"
  rm -f -- /etc/xdg/autostart/aoc-i1659fwux-displaylink.desktop
  rm -f -- /usr/local/libexec/aoc-i1659fwux-session-request.sh
  rm -f -- /usr/local/bin/aoc-i1659fwux-session-request
  rm -rf -- /run/aoc-i1659fwux-displaylink
  restore_evdi_config

  udevadm control --reload-rules >/dev/null 2>&1 || true
  depmod -a || true
  systemctl daemon-reload

  if lsmod 2>/dev/null | awk '{print $1}' | grep -qx evdi; then
    warn "EVDI is still in memory because the graphical session is using it. It will be gone after the next normal reboot."
  fi

  if (( KEEP_BACKUP == 1 )); then
    local backup="/var/backups/${PACKAGE_NAME}-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$(dirname -- "$backup")"
    mv -- "${STATE_DIR}" "$backup"
    log "Installation state preserved at ${backup}."
  else
    rm -rf -- "${STATE_DIR}"
  fi

  log "Uninstallation completed."
  log "Dependency packages were retained to avoid removing software another program may use."
  log "No login, authentication, network, boot, compositor, or desktop-session setting was changed."
  log "No automatic reboot was performed."
}

main "$@"
