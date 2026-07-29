#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || exec sudo "$0" "$@"
STATE_DIR="/var/lib/displaylink-rpi-safe"
STATE_FILE="${STATE_DIR}/state"
REMOVE_OFFICIAL=0

if [[ "${1:-}" == "--remove-official-driver" ]]; then
    REMOVE_OFFICIAL=1
elif [[ -n "${1:-}" ]]; then
    echo "Usage: $0 [--remove-official-driver]" >&2
    exit 2
fi

get_state() { sed -n "s/^$1=//p" "$STATE_FILE" 2>/dev/null | tail -n1; }
VENDOR_SERVICE="$(get_state VENDOR_SERVICE)"
VENDOR_SERVICE="${VENDOR_SERVICE:-displaylink-driver.service}"
VENDOR_WAS_ENABLED="$(get_state VENDOR_SERVICE_WAS_ENABLED)"
VENDOR_WAS_ACTIVE="$(get_state VENDOR_SERVICE_WAS_ACTIVE)"
OFFICIAL_PREEXISTED="$(get_state OFFICIAL_DRIVER_PREEXISTED)"
OFFICIAL_INTERNAL_INSTALLER="$(get_state OFFICIAL_INTERNAL_INSTALLER)"

restore_migrated_evdi_state_if_present() {
    local backup_dir="${STATE_DIR}/evdi-boot-config"
    local manifest="${backup_dir}/manifest"
    [[ -f "$manifest" ]] || return 0
    local state path rel
    while IFS='|' read -r state path; do
        [[ -n "$path" ]] || continue
        rm -rf -- "$path"
        if [[ "$state" == "EXISTS" ]]; then
            rel="${path#/}"
            if [[ -e "$backup_dir/root/$rel" || -L "$backup_dir/root/$rel" ]]; then
                install -d -m 0755 "$(dirname "$path")"
                cp -a "$backup_dir/root/$rel" "$path"
            fi
        fi
    done <"$manifest"
}

systemctl disable --now aoc-i1659fwux-session-broker.service 2>/dev/null || true
systemctl disable --now aoc-i1659fwux-runtime.service 2>/dev/null || true
systemctl stop "$VENDOR_SERVICE" 2>/dev/null || true
/usr/local/sbin/aoc-i1659fwux-usb-control deny 2>/dev/null || true

rm -f \
    /etc/systemd/system/aoc-i1659fwux-session-broker.service \
    /etc/systemd/system/aoc-i1659fwux-runtime.service \
    /usr/local/sbin/aoc-i1659fwux-session-broker \
    /usr/local/sbin/aoc-i1659fwux-usb-control \
    /usr/local/sbin/aoc-i1659fwux-udev-policy \
    /usr/local/sbin/aoc-i1659fwux-status \
    /usr/local/sbin/aoc-i1659fwux-repair \
    /usr/local/sbin/aoc-i1659fwux-uninstall \
    /etc/udev/rules.d/00-aoc-i1659fwux-quarantine.rules \
    /etc/initramfs-tools/hooks/aoc-i1659fwux-quarantine \
    "/etc/systemd/system/${VENDOR_SERVICE}.d/90-aoc-i1659fwux-post-login.conf"
rmdir "/etc/systemd/system/${VENDOR_SERVICE}.d" 2>/dev/null || true

rm -f /etc/udev/rules.d/99-displaylink.rules
if [[ -e "${STATE_DIR}/vendor-udev/99-displaylink.rules.original" || \
      -L "${STATE_DIR}/vendor-udev/99-displaylink.rules.original" ]]; then
    cp -a "${STATE_DIR}/vendor-udev/99-displaylink.rules.original" \
        /etc/udev/rules.d/99-displaylink.rules
fi

restore_migrated_evdi_state_if_present
systemctl unmask "$VENDOR_SERVICE" 2>/dev/null || true
systemctl daemon-reload
udevadm control --reload-rules 2>/dev/null || true

# The exact AOC device may still be deauthorized from the package's last safe
# state. Re-authorize it now that the quarantine rule has been removed.
for dev in /sys/bus/usb/devices/*; do
    [[ -r "$dev/idVendor" && -r "$dev/idProduct" && -w "$dev/authorized" ]] || continue
    [[ "$(cat "$dev/idVendor"):$(cat "$dev/idProduct")" == "17e9:ff10" ]] || continue
    printf 1 >"$dev/authorized" || true
done
udevadm settle --timeout=15 2>/dev/null || true

if (( REMOVE_OFFICIAL )) || [[ "$OFFICIAL_PREEXISTED" != "1" ]]; then
    if [[ -n "$OFFICIAL_INTERNAL_INSTALLER" && -x "$OFFICIAL_INTERNAL_INSTALLER" ]]; then
        (cd "$(dirname "$OFFICIAL_INTERNAL_INSTALLER")" && ./displaylink-installer.sh uninstall) || true
    elif [[ -x /opt/displaylink/displaylink-installer.sh ]]; then
        /opt/displaylink/displaylink-installer.sh uninstall || true
    else
        systemctl disable --now displaylink-driver.service displaylink.service 2>/dev/null || true
        rm -f /etc/systemd/system/displaylink-driver.service /etc/systemd/system/displaylink.service
        rm -f /lib/systemd/system/displaylink-driver.service /usr/lib/systemd/system/displaylink-driver.service
        rm -rf /opt/displaylink
        rm -f /etc/udev/rules.d/99-displaylink.rules /lib/udev/rules.d/99-displaylink.rules /usr/lib/udev/rules.d/99-displaylink.rules
        rm -f /etc/X11/xorg.conf.d/20-displaylink.conf
        for version in $(dkms status 2>/dev/null | sed -n 's/^evdi\/\([^,]*\).*/\1/p'); do
            dkms remove "evdi/${version}" --all 2>/dev/null || true
        done
    fi
else
    [[ "$VENDOR_WAS_ENABLED" == "1" ]] && systemctl enable "$VENDOR_SERVICE" 2>/dev/null || true
    [[ "$VENDOR_WAS_ACTIVE" == "1" ]] && systemctl start "$VENDOR_SERVICE" 2>/dev/null || true
fi

if command -v update-initramfs >/dev/null 2>&1 && \
   ls /boot/initrd.img-* /boot/firmware/initrd.img-* >/dev/null 2>&1; then
    update-initramfs -u -k "$(uname -r)" || true
fi

rm -rf "$STATE_DIR"
systemctl daemon-reload

echo "AOC boot-safe DisplayLink package removed. Login, SSH, PAM, and autologin configuration were not changed."
