#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 022

PACKAGE_NAME="aoc-i1659fwux-rpi-displaylink"
PACKAGE_VERSION="0.4.0"
DRIVER_VERSION="6.3"
EULA_PAGE="https://www.synaptics.com/products/displaylink-usb-graphics-software-ubuntu-63?filetype=exe"
ARCHIVE_URL="https://www.synaptics.com/sites/default/files/exe_files/2026-06/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.3-EXE.zip"
ARCHIVE_SHA256="7269856c7527060c513215ce1b5a36fef074d8e89cab89bcab13df342acce098"
AOC_VENDOR="17e9"
AOC_PRODUCT="ff10"
STATE_DIR="/var/lib/displaylink-rpi-safe"
STATE_FILE="${STATE_DIR}/state"
BACKUP_DIR="${STATE_DIR}/backup"
LOG_FILE="${STATE_DIR}/install.log"
CONTROL_HELPER="/usr/local/sbin/aoc-i1659fwux-usb-control"
UDEV_POLICY_HELPER="/usr/local/sbin/aoc-i1659fwux-udev-policy"
BROKER_HELPER="/usr/local/sbin/aoc-i1659fwux-session-broker"
UDEV_RULE="/etc/udev/rules.d/00-aoc-i1659fwux-quarantine.rules"
VENDOR_RULE_OVERRIDE="/etc/udev/rules.d/99-displaylink.rules"
BROKER_UNIT="aoc-i1659fwux-session-broker.service"
BROKER_UNIT_PATH="/etc/systemd/system/${BROKER_UNIT}"
INITRAMFS_HOOK="/etc/initramfs-tools/hooks/aoc-i1659fwux-quarantine"
EVDI_BOOT_BACKUP_DIR="${STATE_DIR}/evdi-boot-config"
EVDI_BOOT_MANIFEST="${EVDI_BOOT_BACKUP_DIR}/manifest"
BUNDLE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATUS_TOOL="/usr/local/sbin/aoc-i1659fwux-status"
REPAIR_TOOL="/usr/local/sbin/aoc-i1659fwux-repair"
UNINSTALL_TOOL="/usr/local/sbin/aoc-i1659fwux-uninstall"
TEMP_BLOCK_ROOT="/etc/systemd/system"
CHECK_ONLY=0
ADOPT_EXISTING=1
OFFICIAL_DRIVER_PREEXISTED=0
OFFICIAL_INTERNAL_INSTALLER=""
VENDOR_WAS_ENABLED=0
VENDOR_WAS_ACTIVE=0
MIGRATED_PACKAGE_STATE=0

log() {
    printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"
}

fail() {
    log "ERROR: $*" >&2
    return 1
}

prompt_exact() {
    local prompt="$1" expected="$2" response=""
    if [[ ! -r /dev/tty ]]; then
        fail "An interactive terminal is required for confirmation prompts."
    fi
    printf '%s' "$prompt" >/dev/tty
    IFS= read -r response </dev/tty || true
    [[ "$response" == "$expected" ]]
}

as_root() {
    if [[ ${EUID} -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

as_target() {
    if [[ ${EUID} -eq 0 ]]; then
        runuser -u "$TARGET_USER" -- "$@"
    else
        sudo -u "$TARGET_USER" "$@"
    fi
}

resolve_target_user() {
    if [[ ${EUID} -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        printf '%s\n' "$SUDO_USER"
        return
    fi
    if [[ ${EUID} -ne 0 ]]; then
        id -un
        return
    fi
    local candidate
    candidate="$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | head -n1 || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return
    fi
    candidate="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false)$/ {print $1; exit}')"
    [[ -n "$candidate" ]] || fail "Could not determine the normal desktop user. Run with sudo from that user's account."
    printf '%s\n' "$candidate"
}

TARGET_USER="$(resolve_target_user)"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" ]] || fail "Could not determine the home directory for ${TARGET_USER}."
BASE_DIR="${TARGET_HOME}/Downloads/DisplayLink-Ubuntu-${DRIVER_VERSION}-official"

usage() {
    cat <<'USAGE'
Usage: ./install.sh [--check-only] [--no-adopt]

  --check-only  Run all non-changing platform and safety checks, then exit.
  --no-adopt    Do not reuse an existing official DisplayLink 6.3 installation.
USAGE
}

while (($#)); do
    case "$1" in
        --check-only) CHECK_ONLY=1 ;;
        --no-adopt) ADOPT_EXISTING=0 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown option: $1" ;;
    esac
    shift
done

[[ -r /etc/os-release ]] || fail "Cannot read /etc/os-release."
# shellcheck disable=SC1091
source /etc/os-release

ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
KERNEL="$(uname -r)"
if [[ -r /proc/device-tree/model ]]; then
    MODEL="$(tr -d '\0' </proc/device-tree/model)"
else
    MODEL="unknown"
fi

platform_check() {
    case "$ARCH" in
        arm64|aarch64) ;;
        *) fail "This package is only for Raspberry Pi ARM64/aarch64; detected ${ARCH}." ;;
    esac
    case "$MODEL" in
        *"Raspberry Pi 4"*|*"Raspberry Pi 5"*) ;;
        *) fail "Supported hardware is Raspberry Pi 4B or Raspberry Pi 5; detected '${MODEL}'." ;;
    esac
    command -v systemctl >/dev/null 2>&1 || fail "systemd is required."
    command -v loginctl >/dev/null 2>&1 || fail "systemd-logind is required."
    command -v udevadm >/dev/null 2>&1 || fail "udev is required."
    command -v modprobe >/dev/null 2>&1 || fail "modprobe is required."
    if [[ ! -e "/lib/modules/${KERNEL}/build" ]]; then
        log "Matching kernel headers are not installed yet; the installer will install them."
    fi
    log "Platform check passed: ${MODEL}; ${PRETTY_NAME:-unknown}; ${ARCH}; kernel ${KERNEL}."
}

power_warning() {
    cat >/dev/tty <<POWER

IMPORTANT POWER REQUIREMENT
---------------------------
The AOC I1659FWUX is USB-powered and is rated at about 8 W. A software driver
cannot prevent that physical 5 V power draw before Linux starts.

For this boot-safe package, connect the monitor through a separately powered,
USB 3 data hub on BOTH Raspberry Pi 4B and Raspberry Pi 5. Do not rely on the
Pi USB port alone for a monitor that already causes the Pi to stall at boot.

This package prevents early DisplayLink/udev/DRM activation. It cannot repair
a pre-Linux electrical brownout, inrush-current problem, or USB over-current
stall. A powered hub is therefore part of the required working setup.

POWER
    prompt_exact 'Type exactly POWER READY to confirm the power requirement: ' 'POWER READY' || {
        log "Cancelled before making changes."
        exit 0
    }
}

protected_paths=(
    /etc/lightdm/lightdm.conf
    /etc/lightdm/lightdm.conf.d
    "/var/lib/AccountsService/users/${TARGET_USER}"
    /etc/pam.d
    /etc/ssh
    /etc/systemd/system/getty@tty1.service.d
    /etc/systemd/system/getty@tty7.service.d
    /etc/systemd/system/default.target
    /etc/systemd/system/display-manager.service
)

snapshot_protected() {
    local output="$1"
    as_root bash -s -- "$output" "$TARGET_USER" <<'SNAP'
set -Eeuo pipefail
output="$1"
target_user="$2"
paths=(
    /etc/lightdm/lightdm.conf
    /etc/lightdm/lightdm.conf.d
    "/var/lib/AccountsService/users/${target_user}"
    /etc/pam.d
    /etc/ssh/sshd_config
    /etc/ssh/sshd_config.d
    /etc/systemd/system/getty@tty1.service.d
    /etc/systemd/system/getty@tty7.service.d
    /etc/systemd/system/default.target
    /etc/systemd/system/display-manager.service
)
: >"$output"
for path in "${paths[@]}"; do
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        printf 'ABSENT|%s\n' "$path" >>"$output"
    elif [[ -L "$path" ]]; then
        printf 'LINK|%s|%s\n' "$path" "$(readlink "$path")" >>"$output"
    elif [[ -f "$path" ]]; then
        printf 'FILE|%s|%s\n' "$path" "$(sha256sum "$path" | awk '{print $1}')" >>"$output"
    elif [[ -d "$path" ]]; then
        while IFS= read -r -d '' item; do
            if [[ -L "$item" ]]; then
                printf 'LINK|%s|%s\n' "$item" "$(readlink "$item")"
            elif [[ -f "$item" ]]; then
                printf 'FILE|%s|%s\n' "$item" "$(sha256sum "$item" | awk '{print $1}')"
            fi
        done < <(find -P "$path" -xdev -print0 | sort -z) >>"$output"
    fi
done
chmod 0644 "$output"
SNAP
}

backup_protected() {
    as_root rm -rf "$BACKUP_DIR"
    as_root install -d -m 0700 "$BACKUP_DIR"
    local list_file="${BACKUP_DIR}/paths.txt" path
    : | as_root tee "$list_file" >/dev/null
    for path in "${protected_paths[@]}"; do
        if as_root test -e "$path" || as_root test -L "$path"; then
            printf '%s\n' "${path#/}" | as_root tee -a "$list_file" >/dev/null
        fi
    done
    if as_root test -s "$list_file"; then
        as_root tar --numeric-owner --acls --xattrs -C / -cpf "${BACKUP_DIR}/protected.tar" -T "$list_file"
    fi
}

restore_protected() {
    local path
    for path in "${protected_paths[@]}"; do
        as_root rm -rf -- "$path"
    done
    if as_root test -f "${BACKUP_DIR}/protected.tar"; then
        as_root tar --numeric-owner --acls --xattrs -C / -xpf "${BACKUP_DIR}/protected.tar"
    fi
}

service_exists() {
    systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -Fxq "$1"
}

find_vendor_service() {
    local unit
    for unit in displaylink-driver.service displaylink.service; do
        if service_exists "$unit"; then
            printf '%s\n' "$unit"
            return 0
        fi
    done
    return 1
}

load_previous_package_state() {
    as_root test -r "$STATE_FILE" || return 0
    local previous_name
    previous_name="$(as_root sed -n 's/^PACKAGE_NAME=//p' "$STATE_FILE" | tail -n1)"
    [[ "$previous_name" == "$PACKAGE_NAME" ]] || return 0

    MIGRATED_PACKAGE_STATE=1
    VENDOR_WAS_ENABLED="$(as_root sed -n 's/^VENDOR_SERVICE_WAS_ENABLED=//p' "$STATE_FILE" | tail -n1)"
    VENDOR_WAS_ACTIVE="$(as_root sed -n 's/^VENDOR_SERVICE_WAS_ACTIVE=//p' "$STATE_FILE" | tail -n1)"
    OFFICIAL_DRIVER_PREEXISTED="$(as_root sed -n 's/^OFFICIAL_DRIVER_PREEXISTED=//p' "$STATE_FILE" | tail -n1)"
    OFFICIAL_INTERNAL_INSTALLER="$(as_root sed -n 's/^OFFICIAL_INTERNAL_INSTALLER=//p' "$STATE_FILE" | tail -n1)"
    VENDOR_WAS_ENABLED="${VENDOR_WAS_ENABLED:-0}"
    VENDOR_WAS_ACTIVE="${VENDOR_WAS_ACTIVE:-0}"
    OFFICIAL_DRIVER_PREEXISTED="${OFFICIAL_DRIVER_PREEXISTED:-0}"
    log "Migrating the rollback state from the previously installed package revision."
}

disable_previous_wrappers() {
    local unit path
    for unit in         displaylink-after-login.service         aoc-i1659fwux-displaylink.service         aoc-i1659fwux-session-broker.service         aoc-i1659fwux-runtime.service; do
        as_root systemctl disable --now "$unit" 2>/dev/null || true
    done
    for path in         /etc/modules-load.d/aoc-i1659fwux-evdi.conf         /etc/modprobe.d/aoc-i1659fwux-evdi.conf         /etc/modprobe.d/evdi.conf.d/aoc-i1659fwux.conf         /etc/systemd/system/aoc-i1659fwux-runtime.service         /etc/systemd/system/aoc-i1659fwux-displaylink.service         /etc/systemd/system/displaylink-after-login.service         /usr/local/sbin/displaylink-after-login-safe         /usr/local/sbin/aoc-i1659fwux-session-guard; do
        as_root rm -f "$path"
    done
    restore_previous_aoc_evdi_policy
    # Do not unload or rewrite the official EVDI boot configuration here. The
    # supplied baseline works because that configuration is left intact while
    # the physical AOC device and vendor service are blocked until login.
    as_root systemctl daemon-reload
}

restore_previous_aoc_evdi_policy() {
    # Revision 0.3.x forced initial_device_count=0 and replaced EVDI preload
    # files. That made this monitor fail to appear on some Raspberry Pi desktop
    # stacks. Restore the exact pre-0.3.x state when its backup is present.
    if as_root test -f "$EVDI_BOOT_MANIFEST"; then
        local state path rel
        while IFS='|' read -r state path; do
            [[ -n "$path" ]] || continue
            as_root rm -rf -- "$path"
            if [[ "$state" == "EXISTS" ]]; then
                rel="${path#/}"
                if as_root test -e "$EVDI_BOOT_BACKUP_DIR/root/$rel" || \
                   as_root test -L "$EVDI_BOOT_BACKUP_DIR/root/$rel"; then
                    as_root install -d -m 0755 "$(dirname "$path")"
                    as_root cp -a "$EVDI_BOOT_BACKUP_DIR/root/$rel" "$path"
                fi
            fi
        done < <(as_root cat "$EVDI_BOOT_MANIFEST")
        as_root rm -rf "$EVDI_BOOT_BACKUP_DIR"
        return 0
    fi

    # Handle an interrupted 0.3.x install that created the managed override
    # before its backup manifest was completed. Remove only files carrying our
    # package marker; never remove an unrelated administrator file.
    local path
    for path in /etc/modules-load.d/evdi.conf /etc/modprobe.d/evdi.conf; do
        if as_root test -f "$path" && \
           as_root grep -Fq 'Managed by aoc-i1659fwux-rpi-displaylink' "$path"; then
            as_root rm -f "$path"
        fi
    done
}

install_early_usb_gate() {
    as_root install -d -m 0700 "$STATE_DIR"

    as_root tee "$UDEV_POLICY_HELPER" >/dev/null <<'POLICY'
#!/usr/bin/env bash
set -u
if [[ -e /run/aoc-i1659fwux-displaylink/allow ]]; then
    printf 'AOC_DISPLAYLINK_ALLOW=1\n'
else
    printf 'AOC_DISPLAYLINK_ALLOW=0\n'
fi
POLICY
    as_root chmod 0755 "$UDEV_POLICY_HELPER"

    as_root tee "$CONTROL_HELPER" >/dev/null <<'CONTROL'
#!/usr/bin/env bash
set -Eeuo pipefail
RUNTIME_DIR="/run/aoc-i1659fwux-displaylink"
VENDOR="17e9"
PRODUCT="ff10"

find_devices() {
    local dev vendor product
    for dev in /sys/bus/usb/devices/*; do
        [[ -r "$dev/idVendor" && -r "$dev/idProduct" ]] || continue
        read -r vendor <"$dev/idVendor" || continue
        read -r product <"$dev/idProduct" || continue
        if [[ "$vendor" == "$VENDOR" && "$product" == "$PRODUCT" ]]; then
            printf '%s\n' "$dev"
        fi
    done
}

set_authorized() {
    local value="$1" dev
    while IFS= read -r dev; do
        [[ -n "$dev" ]] || continue
        if [[ -w "$dev/authorized" ]]; then
            printf '%s' "$value" >"$dev/authorized" || true
        fi
    done < <(find_devices)
}

case "${1:-}" in
    deny|quarantine)
        rm -f "${RUNTIME_DIR}/allow"
        set_authorized 0
        ;;
    allow)
        install -d -m 0755 "$RUNTIME_DIR"
        : >"${RUNTIME_DIR}/allow"
        set_authorized 1
        udevadm settle --timeout=15 2>/dev/null || true
        ;;
    list)
        find_devices
        ;;
    *)
        echo "Usage: $0 {deny|allow|list}" >&2
        exit 2
        ;;
esac
CONTROL
    as_root chmod 0755 "$CONTROL_HELPER"

    as_root tee "$UDEV_RULE" >/dev/null <<'RULE'
# AOC I1659FWUX boot quarantine. This exact USB device remains unauthorized
# until the post-login broker creates /run/aoc-i1659fwux-displaylink/allow.
ACTION=="add|change|bind", SUBSYSTEM=="usb", ATTR{idVendor}=="17e9", ATTR{idProduct}=="ff10", IMPORT{program}="/usr/local/sbin/aoc-i1659fwux-udev-policy"
ACTION=="add|change|bind", SUBSYSTEM=="usb", ATTR{idVendor}=="17e9", ATTR{idProduct}=="ff10", ENV{AOC_DISPLAYLINK_ALLOW}!="1", ATTR{authorized}="0"
RULE
    as_root chmod 0644 "$UDEV_RULE"
    as_root udevadm control --reload-rules
    as_root "$CONTROL_HELPER" deny || true
}

install_initramfs_hook_if_applicable() {
    if [[ ! -d /etc/initramfs-tools || ! -x "$(command -v update-initramfs 2>/dev/null || true)" ]]; then
        return 0
    fi
    as_root tee "$INITRAMFS_HOOK" >/dev/null <<'HOOK'
#!/bin/sh
set -e
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
mkdir -p "${DESTDIR}/etc/udev/rules.d" "${DESTDIR}/usr/local/sbin"
cp -a /etc/udev/rules.d/00-aoc-i1659fwux-quarantine.rules "${DESTDIR}/etc/udev/rules.d/"
copy_exec /usr/local/sbin/aoc-i1659fwux-udev-policy /usr/local/sbin
HOOK
    as_root chmod 0755 "$INITRAMFS_HOOK"
    if ls /boot/initrd.img-* /boot/firmware/initrd.img-* >/dev/null 2>&1; then
        log "Updating the already-configured initramfs with the exact-device USB quarantine rule."
        as_root update-initramfs -u -k "$KERNEL" || log "WARNING: initramfs update failed; root-filesystem udev quarantine remains installed."
    fi
}

backup_and_disable_vendor_udev_rule() {
    as_root install -d -m 0700 "${STATE_DIR}/vendor-udev"
    local saved="${STATE_DIR}/vendor-udev/99-displaylink.rules.original"

    # Keep the real original retained by an earlier revision. Do not replace it
    # with that revision's /dev/null override during an in-place upgrade.
    if as_root test -e "$saved" || as_root test -L "$saved"; then
        printf 'VENDOR_RULE_IN_ETC=1\n' | as_root tee -a "$STATE_FILE" >/dev/null
    elif as_root test -e "$VENDOR_RULE_OVERRIDE" || as_root test -L "$VENDOR_RULE_OVERRIDE"; then
        if [[ "$(as_root readlink "$VENDOR_RULE_OVERRIDE" 2>/dev/null || true)" != "/dev/null" ]]; then
            as_root cp -a "$VENDOR_RULE_OVERRIDE" "$saved"
            printf 'VENDOR_RULE_IN_ETC=1\n' | as_root tee -a "$STATE_FILE" >/dev/null
        else
            printf 'VENDOR_RULE_IN_ETC=0\n' | as_root tee -a "$STATE_FILE" >/dev/null
        fi
    else
        printf 'VENDOR_RULE_IN_ETC=0\n' | as_root tee -a "$STATE_FILE" >/dev/null
    fi
    as_root rm -f "$VENDOR_RULE_OVERRIDE"
    as_root ln -s /dev/null "$VENDOR_RULE_OVERRIDE"
    as_root udevadm control --reload-rules
}

install_support_tools() {
    [[ -f "${BUNDLE_DIR}/status.sh" ]] || fail "Bundle is missing status.sh."
    [[ -f "${BUNDLE_DIR}/repair-login.sh" ]] || fail "Bundle is missing repair-login.sh."
    [[ -f "${BUNDLE_DIR}/uninstall.sh" ]] || fail "Bundle is missing uninstall.sh."
    as_root install -m 0755 "${BUNDLE_DIR}/status.sh" "$STATUS_TOOL"
    as_root install -m 0755 "${BUNDLE_DIR}/repair-login.sh" "$REPAIR_TOOL"
    as_root install -m 0755 "${BUNDLE_DIR}/uninstall.sh" "$UNINSTALL_TOOL"
}

configure_vendor_service_post_login() {
    local vendor_service="$1"
    local dropin_dir="/etc/systemd/system/${vendor_service}.d"
    local dropin_path="${dropin_dir}/90-aoc-i1659fwux-post-login.conf"

    as_root install -d -m 0755 "$dropin_dir"
    as_root tee "$dropin_path" >/dev/null <<'DROPIN'
[Unit]
# Remove the vendor tty/getty conflict and refuse every pre-login start.
Conflicts=
ConditionPathExists=/run/aoc-i1659fwux-displaylink/allow
After=systemd-udevd.service
DROPIN
    as_root chmod 0644 "$dropin_path"
    as_root systemctl unmask "$vendor_service" 2>/dev/null || true
    as_root systemctl daemon-reload
    as_root systemctl disable --now "$vendor_service" 2>/dev/null || true
}

install_broker() {
    as_root tee "$BROKER_HELPER" >/dev/null <<'BROKER'
#!/usr/bin/env bash
set -Eeuo pipefail
STATE_FILE="/var/lib/displaylink-rpi-safe/state"
CONTROL="/usr/local/sbin/aoc-i1659fwux-usb-control"
LOG="/var/lib/displaylink-rpi-safe/broker.log"

install -d -m 0700 /var/lib/displaylink-rpi-safe
exec >>"$LOG" 2>&1

TARGET_USER="$(sed -n 's/^TARGET_USER=//p' "$STATE_FILE" | tail -n1)"
VENDOR_SERVICE="$(sed -n 's/^VENDOR_SERVICE=//p' "$STATE_FILE" | tail -n1)"
[[ -n "$TARGET_USER" && -n "$VENDOR_SERVICE" ]] || exit 1

log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

session_is_graphical() {
    local sid="$1" name active type class remote state
    name="$(loginctl show-session "$sid" -p Name --value 2>/dev/null || true)"
    active="$(loginctl show-session "$sid" -p Active --value 2>/dev/null || true)"
    type="$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)"
    class="$(loginctl show-session "$sid" -p Class --value 2>/dev/null || true)"
    remote="$(loginctl show-session "$sid" -p Remote --value 2>/dev/null || true)"
    state="$(loginctl show-session "$sid" -p State --value 2>/dev/null || true)"
    [[ "$name" == "$TARGET_USER" && "$active" == "yes" && "$remote" != "yes" && \
       "$class" != "greeter" && ( "$type" == "x11" || "$type" == "wayland" ) && \
       ( "$state" == "active" || "$state" == "online" ) ]]
}

find_session() {
    local sid
    while read -r sid _; do
        [[ -n "$sid" ]] || continue
        if session_is_graphical "$sid"; then
            printf '%s\n' "$sid"
            return 0
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
    return 1
}

stop_displaylink() {
    systemctl stop "$VENDOR_SERVICE" 2>/dev/null || true
    "$CONTROL" deny || true
}

trap stop_displaylink EXIT
trap 'exit 0' TERM INT
stop_displaylink
log "Waiting for authenticated graphical session for ${TARGET_USER}."

LAST_FAILED_SESSION=""
while true; do
    SESSION="$(find_session || true)"
    if [[ -z "$SESSION" ]]; then
        sleep 2
        continue
    fi
    if [[ "$SESSION" == "$LAST_FAILED_SESSION" ]]; then
        sleep 3
        continue
    fi

    log "Session ${SESSION} is active. Waiting 12 seconds before reproducing the known-good USB hot-plug sequence."
    sleep 12
    if ! session_is_graphical "$SESSION"; then
        continue
    fi

    "$CONTROL" allow
    sleep 2
    if ! systemctl start "$VENDOR_SERVICE"; then
        log "Official DisplayLink service failed to start; returning the monitor to quarantine for this session."
        LAST_FAILED_SESSION="$SESSION"
        stop_displaylink
        continue
    fi

    log "Official DisplayLink service started after login."
    while session_is_graphical "$SESSION" && systemctl is-active --quiet "$VENDOR_SERVICE"; do
        sleep 2
    done

    if session_is_graphical "$SESSION"; then
        log "DisplayLink ended while the desktop remained active; quarantining until a new session."
        LAST_FAILED_SESSION="$SESSION"
    else
        log "Desktop session ended; stopping DisplayLink before the greeter returns."
        LAST_FAILED_SESSION=""
    fi
    stop_displaylink
    sleep 2
done
BROKER
    as_root chmod 0755 "$BROKER_HELPER"

    as_root tee "$BROKER_UNIT_PATH" >/dev/null <<'UNIT'
[Unit]
Description=AOC I1659FWUX post-login DisplayLink broker
After=systemd-logind.service multi-user.target
Wants=systemd-logind.service
ConditionPathExists=/opt/displaylink/DisplayLinkManager

[Service]
Type=simple
ExecStart=/usr/local/sbin/aoc-i1659fwux-session-broker
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

    as_root systemctl daemon-reload
    as_root systemctl enable --now "$BROKER_UNIT"
}

record_state() {
    local vendor_service="$1"
    as_root install -d -m 0700 "$STATE_DIR"
    {
        printf 'PACKAGE_NAME=%s\n' "$PACKAGE_NAME"
        printf 'PACKAGE_VERSION=%s\n' "$PACKAGE_VERSION"
        printf 'TARGET_USER=%s\n' "$TARGET_USER"
        printf 'TARGET_HOME=%s\n' "$TARGET_HOME"
        printf 'VENDOR_SERVICE=%s\n' "$vendor_service"
        printf 'VENDOR_SERVICE_WAS_ENABLED=%s\n' "$VENDOR_WAS_ENABLED"
        printf 'VENDOR_SERVICE_WAS_ACTIVE=%s\n' "$VENDOR_WAS_ACTIVE"
        printf 'OFFICIAL_DRIVER_PREEXISTED=%s\n' "$OFFICIAL_DRIVER_PREEXISTED"
        printf 'OFFICIAL_INTERNAL_INSTALLER=%s\n' "$OFFICIAL_INTERNAL_INSTALLER"
        printf 'INSTALL_KERNEL=%s\n' "$KERNEL"
        printf 'INSTALL_MODEL=%s\n' "$MODEL"
    } | as_root tee "$STATE_FILE" >/dev/null
    as_root chmod 0600 "$STATE_FILE"
}

stop_vendor_service() {
    local vendor_service="$1"
    as_root systemctl disable --now "$vendor_service" 2>/dev/null || true
}

install_dependencies_and_headers() {
    log "Installing only DisplayLink/EVDI build and runtime dependencies."
    as_root apt-get update
    as_root apt-get install -y ca-certificates curl unzip dkms build-essential binutils libdrm-dev libelf-dev libusb-1.0-0 libstdc++6 usbutils pkg-config
    if [[ ! -e "/lib/modules/${KERNEL}/build" ]]; then
        if ! as_root apt-get install -y "linux-headers-${KERNEL}"; then
            as_root apt-get install -y raspberrypi-kernel-headers || fail "Matching kernel headers could not be installed."
        fi
    fi
    [[ -e "/lib/modules/${KERNEL}/build" ]] || fail "Kernel headers do not match ${KERNEL}; reboot after updating and rerun."
}

install_temporary_vendor_start_block() {
    local unit dir
    for unit in displaylink-driver.service displaylink.service; do
        dir="${TEMP_BLOCK_ROOT}/${unit}.d"
        as_root install -d -m 0755 "$dir"
        as_root tee "${dir}/00-aoc-safe-install.conf" >/dev/null <<'DROPIN'
[Unit]
Conflicts=

[Service]
Type=oneshot
ExecStartPre=
ExecStart=
ExecStart=/bin/true
ExecStop=
ExecStopPost=
Restart=no
RemainAfterExit=yes
DROPIN
    done
    as_root systemctl daemon-reload
}

remove_temporary_vendor_start_block() {
    local unit
    for unit in displaylink-driver.service displaylink.service; do
        as_root rm -f "${TEMP_BLOCK_ROOT}/${unit}.d/00-aoc-safe-install.conf"
        as_root rmdir "${TEMP_BLOCK_ROOT}/${unit}.d" 2>/dev/null || true
    done
    as_root systemctl daemon-reload
}

install_official_driver() {
    if [[ -x /opt/displaylink/DisplayLinkManager && "$ADOPT_EXISTING" == "1" ]]; then
        if (( ! MIGRATED_PACKAGE_STATE )); then
            OFFICIAL_DRIVER_PREEXISTED=1
        fi
        log "Adopting the existing official DisplayLink installation; vendor files will not be reinstalled."
        return 0
    fi
    OFFICIAL_DRIVER_PREEXISTED=0

    install_dependencies_and_headers
    if [[ -e "$BASE_DIR" ]]; then
        BASE_DIR="${BASE_DIR}-$(date +%Y%m%d-%H%M%S)"
    fi
    install -d -m 0755 "$BASE_DIR"
    as_root chown "$TARGET_USER:$TARGET_USER" "$BASE_DIR"
    local archive_path="${BASE_DIR}/DisplayLink-USB-Graphics-Software-for-Ubuntu-${DRIVER_VERSION}.zip"
    log "Downloading the official Synaptics DisplayLink ${DRIVER_VERSION} archive."
    as_target curl --fail --location --show-error --output "$archive_path" "$ARCHIVE_URL"
    [[ -s "$archive_path" ]] || fail "The downloaded archive is empty."
    local actual
    actual="$(sha256sum "$archive_path" | awk '{print $1}')"
    [[ "$actual" == "$ARCHIVE_SHA256" ]] || fail "Official archive checksum mismatch: ${actual}."
    unzip -tq "$archive_path"
    local extract_dir="${BASE_DIR}/extracted"
    as_target mkdir -p "$extract_dir"
    as_target unzip -q "$archive_path" -d "$extract_dir"
    mapfile -d '' run_files < <(find "$extract_dir" -type f -name 'displaylink-driver-*.run' -print0)
    (( ${#run_files[@]} == 1 )) || fail "Expected exactly one DisplayLink .run installer."
    local run_file="${run_files[0]}" run_unpack="${BASE_DIR}/official-run"
    chmod 0755 "$run_file"
    as_target mkdir -p "$run_unpack"
    (cd "$run_unpack" && "$run_file" --noexec --keep)
    mapfile -d '' internal_installers < <(find "$run_unpack" -type f -name displaylink-installer.sh -print0)
    (( ${#internal_installers[@]} == 1 )) || fail "Expected exactly one official internal installer."
    local internal_installer="${internal_installers[0]}"
    chmod 0755 "$internal_installer"
    log "Running the unmodified official internal DisplayLink installer with a temporary no-op service override so it cannot start before login."
    install_temporary_vendor_start_block
    if ! (cd "$(dirname "$internal_installer")" && as_root ./displaylink-installer.sh install); then
        remove_temporary_vendor_start_block
        fail "The official DisplayLink installer failed."
    fi
    # Keep the temporary no-op drop-in until the permanent post-login guard and
    # vendor udev override are both installed, eliminating the service-start
    # race between the official installer and our broker setup.
    OFFICIAL_INTERNAL_INSTALLER="$internal_installer"
}

recover_on_error() {
    local exit_code=$? current_snapshot=""
    trap - ERR
    log "Installation failed; disabling DisplayLink startup."
    as_root systemctl disable --now "$BROKER_UNIT" 2>/dev/null || true
    as_root "$CONTROL_HELPER" deny 2>/dev/null || true
    for failed_unit in displaylink-driver.service displaylink.service; do
        as_root systemctl disable --now "$failed_unit" 2>/dev/null || true
    done
    as_root rm -f "$VENDOR_RULE_OVERRIDE" 2>/dev/null || true
    as_root ln -s /dev/null "$VENDOR_RULE_OVERRIDE" 2>/dev/null || true
    remove_temporary_vendor_start_block 2>/dev/null || true
    as_root systemctl daemon-reload 2>/dev/null || true
    as_root udevadm control --reload-rules 2>/dev/null || true
    if [[ -n "${local_before:-}" && -f "${local_before:-}" ]]; then
        current_snapshot="$(mktemp)"
        snapshot_protected "$current_snapshot" || true
        if ! cmp -s "$local_before" "$current_snapshot"; then
            log "A protected login/SSH file changed during the failed installation; restoring the exact snapshot."
            restore_protected || true
        fi
        rm -f "$current_snapshot"
    fi
    exit "$exit_code"
}

platform_check
if (( CHECK_ONLY )); then
    log "Safety and compatibility checks passed. No changes were made."
    exit 0
fi

power_warning
cat >/dev/tty <<LICENSE

The proprietary DisplayLink user-space files are governed by the Synaptics EULA:
${EULA_PAGE}

LICENSE
prompt_exact 'Type AGREE to confirm that you reviewed and accept the EULA: ' 'AGREE' || {
    log "EULA not accepted. No changes were made."
    exit 0
}

as_root install -d -m 0700 "$STATE_DIR"
exec > >(as_root tee -a "$LOG_FILE") 2>&1
trap recover_on_error ERR

log "Beginning ${PACKAGE_NAME} ${PACKAGE_VERSION} installation."
local_before="$(mktemp)"
local_after="$(mktemp)"
trap 'rm -f "$local_before" "$local_after"' EXIT
snapshot_protected "$local_before"
backup_protected
load_previous_package_state
disable_previous_wrappers
install_early_usb_gate
install_initramfs_hook_if_applicable

vendor_service="$(find_vendor_service || true)"
if [[ -n "$vendor_service" ]]; then
    if (( ! MIGRATED_PACKAGE_STATE )); then
        systemctl is-enabled --quiet "$vendor_service" 2>/dev/null && VENDOR_WAS_ENABLED=1 || true
        systemctl is-active --quiet "$vendor_service" 2>/dev/null && VENDOR_WAS_ACTIVE=1 || true
    fi
    stop_vendor_service "$vendor_service"
fi

install_official_driver
vendor_service="$(find_vendor_service || true)"
[[ -n "$vendor_service" ]] || fail "Official installer completed but no DisplayLink system service was found."
stop_vendor_service "$vendor_service"
record_state "$vendor_service"
backup_and_disable_vendor_udev_rule
install_support_tools
configure_vendor_service_post_login "$vendor_service"
remove_temporary_vendor_start_block
install_broker
snapshot_protected "$local_after"
if ! cmp -s "$local_before" "$local_after"; then
    restore_protected
    fail "Protected login, authentication, SSH, or display-manager files changed; they were restored and the installation was stopped."
fi
trap - ERR

log "Installation completed without changing protected login or SSH configuration."
cat <<DONE

The AOC monitor is now quarantined during boot and at the login screen.
It is authorized and DisplayLinkManager is started only after the existing
${TARGET_USER} desktop session is active.

The official vendor service remains disabled at boot. Its generic udev rule is
blocked, and a service drop-in removes its tty/getty conflict and requires the
post-login allow marker. The broker starts the same known-working official
service only after your existing desktop is active.

Reboot with the monitor connected through the mandatory separately powered USB 3 hub:
  sudo reboot

Status:
  sudo /usr/local/sbin/aoc-i1659fwux-status

Emergency safe mode:
  sudo /usr/local/sbin/aoc-i1659fwux-repair

DONE
