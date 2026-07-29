#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || exec sudo "$0" "$@"
STATE_DIR="/var/lib/displaylink-rpi-safe"
STATE_FILE="${STATE_DIR}/state"
CONTROL="/usr/local/sbin/aoc-i1659fwux-usb-control"
BROKER="aoc-i1659fwux-session-broker.service"
VENDOR_SERVICE="$(sed -n 's/^VENDOR_SERVICE=//p' "$STATE_FILE" 2>/dev/null | tail -n1)"
VENDOR_SERVICE="${VENDOR_SERVICE:-displaylink-driver.service}"

log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

if [[ "${1:-}" == "--enable" ]]; then
    systemctl unmask "$VENDOR_SERVICE" 2>/dev/null || true
    systemctl disable --now "$VENDOR_SERVICE" 2>/dev/null || true
    systemctl daemon-reload
    systemctl enable --now "$BROKER"
    cat <<DONE

The corrected post-login broker is enabled again.
The official DisplayLink service remains disabled at boot and can start only
after the broker creates its authenticated-session allow marker.

Check status with:
  sudo /usr/local/sbin/aoc-i1659fwux-status

DONE
    exit 0
elif [[ -n "${1:-}" ]]; then
    echo "Usage: $0 [--enable]" >&2
    exit 2
fi

log "Stopping every package and legacy DisplayLink startup path."
for unit in \
    "$BROKER" \
    aoc-i1659fwux-runtime.service \
    displaylink-after-login.service \
    aoc-i1659fwux-displaylink.service; do
    systemctl disable --now "$unit" 2>/dev/null || true
done

for unit in displaylink-driver.service displaylink.service; do
    if systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -Fxq "$unit"; then
        systemctl disable --now "$unit" 2>/dev/null || true
        systemctl mask --now --force "$unit" >/dev/null 2>&1 || true
    fi
done

rm -rf /run/aoc-i1659fwux-displaylink
if [[ -x "$CONTROL" ]]; then
    "$CONTROL" deny || true
else
    for dev in /sys/bus/usb/devices/*; do
        [[ -r "$dev/idVendor" && -r "$dev/idProduct" && -w "$dev/authorized" ]] || continue
        [[ "$(cat "$dev/idVendor"):$(cat "$dev/idProduct")" == "17e9:ff10" ]] || continue
        printf 0 >"$dev/authorized" || true
    done
fi

modprobe -r evdi 2>/dev/null || true
systemctl daemon-reload
udevadm control --reload-rules 2>/dev/null || true

cat <<'DONE'

DisplayLink is now in emergency safe mode:
  - the official vendor service is masked;
  - the AOC USB device is quarantined;
  - EVDI is unloaded;
  - no login, password, PAM, LightDM, SSH, or autologin file was changed.

Reboot with HDMI connected. The AOC may remain physically connected only when
it is connected through a separately powered USB 3 hub:

  sudo reboot

After confirming the original desktop/login behaviour is restored, re-enable
the corrected post-login broker with:

  sudo /usr/local/sbin/aoc-i1659fwux-repair --enable

DONE
