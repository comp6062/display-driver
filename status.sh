#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="/var/lib/displaylink-rpi-safe"
STATE_FILE="${STATE_DIR}/state"
CONTROL="/usr/local/sbin/aoc-i1659fwux-usb-control"
BROKER_UNIT="aoc-i1659fwux-session-broker.service"
VENDOR_SERVICE="$(sed -n 's/^VENDOR_SERVICE=//p' "$STATE_FILE" 2>/dev/null | tail -n1)"
VENDOR_SERVICE="${VENDOR_SERVICE:-displaylink-driver.service}"

section() { printf '\n===== %s =====\n' "$1"; }
value() { systemctl "$@" 2>/dev/null || true; }

section "PLATFORM"
printf 'Model:        %s\n' "$(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo unknown)"
printf 'OS:           %s\n' "$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")"
printf 'Architecture: %s\n' "$(dpkg --print-architecture 2>/dev/null || uname -m)"
printf 'Kernel:       %s\n' "$(uname -r)"

section "PACKAGE STATE"
if [[ -r "$STATE_FILE" ]]; then
    grep -E '^(PACKAGE_VERSION|TARGET_USER|VENDOR_SERVICE|OFFICIAL_DRIVER_PREEXISTED|INSTALL_KERNEL|INSTALL_MODEL)=' "$STATE_FILE" || true
else
    echo "No package state file found."
fi

section "USB DEVICE 17e9:ff10"
found=0
for dev in /sys/bus/usb/devices/*; do
    [[ -r "$dev/idVendor" && -r "$dev/idProduct" ]] || continue
    vendor="$(cat "$dev/idVendor")"
    product="$(cat "$dev/idProduct")"
    [[ "$vendor:$product" == "17e9:ff10" ]] || continue
    found=1
    printf 'Path:       %s\n' "$dev"
    printf 'Authorized: %s\n' "$(cat "$dev/authorized" 2>/dev/null || echo unknown)"
    printf 'Bus/dev:    %s/%s\n' "$(cat "$dev/busnum" 2>/dev/null || echo '?')" "$(cat "$dev/devnum" 2>/dev/null || echo '?')"
    printf 'Speed:      %s Mb/s\n' "$(cat "$dev/speed" 2>/dev/null || echo unknown)"
done
(( found )) || echo "Monitor is not currently enumerated."

section "SERVICES"
for unit in displaylink-driver.service displaylink.service "$BROKER_UNIT"; do
    printf '%-44s enabled=%-10s active=%s\n' \
        "$unit" \
        "$(systemctl is-enabled "$unit" 2>/dev/null || echo absent)" \
        "$(systemctl is-active "$unit" 2>/dev/null || echo inactive)"
done

section "SESSIONS"
loginctl list-sessions --no-legend 2>/dev/null || true
for sid in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
    echo "--- session ${sid} ---"
    loginctl show-session "$sid" -p Name -p Active -p State -p Type -p Class -p Remote 2>/dev/null || true
done

section "BASELINE EVDI CONFIGURATION"
for path in /etc/modules /etc/modules-load.d/evdi.conf /etc/modules-load.d/displaylink.conf /etc/modprobe.d/evdi.conf /etc/modprobe.d/displaylink.conf; do
    if [[ -e "$path" || -L "$path" ]]; then
        echo "--- ${path} ---"
        grep -nE '(^|[[:space:]])evdi([[:space:]]|$)|initial_device_count' "$path" 2>/dev/null || echo "No EVDI preload directive."
    fi
done

section "EVDI / DISPLAYLINK"
lsmod | awk 'NR==1 || $1=="evdi"' || true
pgrep -a DisplayLinkManager || echo "DisplayLinkManager is not running."

section "DRM CONNECTORS"
native_mode_found=0
for status in /sys/class/drm/card*-*/status; do
    [[ -e "$status" ]] || continue
    connector="${status%/status}"
    printf '%s: %s' "$(basename "$connector")" "$(cat "$status")"
    if [[ -r "$connector/modes" ]]; then
        modes="$(tr '\n' ' ' <"$connector/modes")"
        printf ' modes=[%s]' "$modes"
        grep -Fxq '1920x1080' "$connector/modes" && native_mode_found=1 || true
    fi
    printf '\n'
done
if (( native_mode_found )); then
    echo "Native 1920x1080 mode is exposed by at least one DRM connector."
else
    echo "Native 1920x1080 mode is not currently exposed."
fi

section "POWER / THROTTLING"
if command -v vcgencmd >/dev/null 2>&1; then
    vcgencmd get_throttled || true
    vcgencmd measure_volts core 2>/dev/null || true
else
    echo "vcgencmd is unavailable."
fi

grep -iE 'under.?voltage|over.?current|usb.*power' /var/log/syslog 2>/dev/null | tail -20 || true

section "RECENT PACKAGE LOG"
tail -80 "${STATE_DIR}/broker.log" 2>/dev/null || echo "No broker log yet."

section "RECENT SERVICE JOURNAL"
journalctl -u "$BROKER_UNIT" -u "$VENDOR_SERVICE" --no-pager -n 80 2>/dev/null || true
