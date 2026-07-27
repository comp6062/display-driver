#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROJECT_NAME="AOC I1659FWUX Raspberry Pi 4/5 DisplayLink Driver"
PROJECT_VERSION="1.1.0-single-file"
DISPLAYLINK_VERSION="6.3"
DISPLAYLINK_ZIP_URL="https://www.synaptics.com/sites/default/files/exe_files/2026-06/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.3-EXE.zip"
DISPLAYLINK_EULA_URL="https://www.synaptics.com/products/displaylink-usb-graphics-software-ubuntu-63?filetype=exe"
AOC_USB_ID="17e9:ff10"
INSTALL_ROOT="/opt/aoc-i1659fwux-displaylink"
STATE_DIR="/var/lib/aoc-i1659fwux-displaylink"
SERVICE_FILE="/etc/systemd/system/aoc-i1659fwux-displaylink.service"
MODPROBE_FILE="/etc/modprobe.d/aoc-i1659fwux-evdi.conf"
MODULES_LOAD_FILE="/etc/modules-load.d/aoc-i1659fwux-evdi.conf"
UDEV_RULE_FILE="/etc/udev/rules.d/85-aoc-i1659fwux-displaylink.rules"
RESOLUTION_HELPER="/usr/local/bin/aoc-i1659fwux-resolution"
DIAGNOSTICS_HELPER="/usr/local/bin/aoc-i1659fwux-diagnostics"
AUTOSTART_FILE="/etc/xdg/autostart/aoc-i1659fwux-resolution.desktop"
LOG_FILE="/var/log/aoc-i1659fwux-displaylink-install.log"
SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"
MANAGER_HELPER="/usr/local/sbin/aoc-i1659fwux-driver"

ACCEPT_EULA=0
ENABLE_RESOLUTION_HELPER=1
FORCE_UNSUPPORTED_KERNEL=0
OFFLINE_ZIP=""
KEEP_DOWNLOAD=0
WORK_DIR=""
DRIVER_ZIP=""
PAYLOAD_DIR=""
EVDI_VERSION=""
EVDI_SOURCE_ROOT=""
INSTALL_STARTED=0
LOG_ACTIVE=0


write_preflight_payload() {
    cat <<'AOC_PREFLIGHT_PAYLOAD_EOF'
#!/usr/bin/env bash
set -u
IFS=$'\n\t'

USB_ID="17e9:ff10"
PASS=0
WARN=0
FAIL=0

ok() { printf '[PASS] %s\n' "$*"; PASS=$((PASS+1)); }
warning() { printf '[WARN] %s\n' "$*"; WARN=$((WARN+1)); }
fail() { printf '[FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$arch" in
    arm64|aarch64) ok "64-bit ARM architecture detected: $arch" ;;
    *) fail "Expected arm64/aarch64, detected: $arch" ;;
esac

if [[ -r /proc/device-tree/model ]]; then
        model="$(tr -d '\0' </proc/device-tree/model)"
    else
        model=""
    fi
if [[ "$model" == *"Raspberry Pi 4"* || "$model" == *"Raspberry Pi 5"* ]]; then
    ok "$model"
else
    fail "Expected Raspberry Pi 4 or Raspberry Pi 5 hardware, detected: ${model:-unknown}"
fi

if [[ -e "/lib/modules/$(uname -r)/build/Makefile" ]]; then
    ok "Matching kernel headers are present for $(uname -r)."
else
    warning "Matching kernel headers are not currently installed for $(uname -r); the installer will try Raspberry Pi OS header packages."
fi

kernel_mm="$(uname -r | grep -oE '^[0-9]+\.[0-9]+' || true)"
if [[ -n "$kernel_mm" ]]; then
    major="${kernel_mm%%.*}"
    minor="${kernel_mm#*.}"
    value=$((10#$major * 1000 + 10#$minor))
    if (( value >= 4015 && value <= 6015 )); then
        ok "Kernel $kernel_mm is within the official DisplayLink 6.3 verified range."
    else
        warning "Kernel $kernel_mm is outside the official verified 4.15-6.15 range."
    fi
else
    fail "Could not parse the kernel version."
fi

if command -v lsusb >/dev/null 2>&1; then
    if lsusb -d "$USB_ID" >/dev/null 2>&1; then
        ok "AOC I1659FWUX detected as USB $USB_ID."
    else
        warning "AOC I1659FWUX USB $USB_ID is not connected. Installation can still proceed."
    fi
else
    warning "lsusb is not installed; the installer will add usbutils."
fi

conflicts=()
[[ -e /opt/displaylink ]] && conflicts+=("/opt/displaylink")
for existing_path in \
    /usr/lib/displaylink \
    /usr/libexec/displaylink \
    /usr/share/displaylink \
    /usr/share/displaylink-driver \
    /etc/udev/rules.d/99-displaylink.rules \
    /etc/modprobe.d/evdi.conf \
    /etc/modules-load.d/evdi.conf \
    /lib/systemd/system/displaylink-driver.service \
    /usr/lib/systemd/system/displaylink-driver.service; do
    [[ -e "$existing_path" ]] && conflicts+=("$existing_path")
done
dpkg-query -W -f='${Status}' displaylink-driver 2>/dev/null | grep -q 'install ok installed' && conflicts+=("displaylink-driver APT package")
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -Eq '^(displaylink-driver|displaylink|dlm)\.service$'; then
    conflicts+=("existing DisplayLink service")
fi
if command -v dkms >/dev/null 2>&1 && dkms status 2>/dev/null | grep -qE '^evdi[/, ]'; then
    conflicts+=("existing EVDI DKMS module")
fi
if lsmod 2>/dev/null | awk '{print $1}' | grep -qx evdi; then
    conflicts+=("already-loaded EVDI kernel module")
fi

if (( ${#conflicts[@]} == 0 )); then
    ok "No conflicting DisplayLink/EVDI installation was detected."
else
    fail "Conflict detected: ${conflicts[*]}. Remove it with its own uninstaller before using this package."
fi

session="${XDG_SESSION_TYPE:-unknown}"
case "$session" in
    x11) ok "X11 session detected; the optional resolution helper can operate." ;;
    wayland) warning "Wayland session detected. The package will not switch sessions or modify the compositor; resolution correction will remain inactive." ;;
    *) warning "Session type is $session. Run this preflight from the graphical desktop for a more complete result." ;;
esac

printf '\nSummary: %d passed, %d warnings, %d failed.\n' "$PASS" "$WARN" "$FAIL"
if (( FAIL > 0 )); then
    exit 1
fi
AOC_PREFLIGHT_PAYLOAD_EOF
}

write_diagnostics_payload() {
    cat <<'AOC_DIAGNOSTICS_PAYLOAD_EOF'
#!/usr/bin/env bash
set -u
IFS=$'\n\t'

USB_ID="17e9:ff10"
OUTPUT_FILE="${1:-$HOME/aoc-i1659fwux-diagnostics-$(date '+%Y%m%d-%H%M%S').txt}"

section() {
    printf '\n================ %s ================\n' "$1"
}

command_output() {
    local title="$1"
    shift
    section "$title"
    "$@" 2>&1 || true
}

{
    printf 'AOC I1659FWUX Raspberry Pi 4/5 DisplayLink diagnostics\n'
    printf 'Generated: %s\n' "$(date --iso-8601=seconds)"

    section "Platform"
    printf 'Kernel: %s\n' "$(uname -a)"
    printf 'Architecture: %s\n' "$(dpkg --print-architecture 2>/dev/null || uname -m)"
    if [[ -r /proc/device-tree/model ]]; then
        printf 'Hardware: %s\n' "$(tr -d '\0' </proc/device-tree/model)"
    else
        printf 'Hardware: unknown\n'
    fi
    printf 'OS release:\n'
    sed -n '1,20p' /etc/os-release 2>/dev/null || true
    printf 'Session type: %s\n' "${XDG_SESSION_TYPE:-unknown}"
    printf 'Desktop: %s\n' "${XDG_CURRENT_DESKTOP:-unknown}"
    printf 'Display variable: %s\n' "${DISPLAY:-unset}"
    printf 'Wayland display: %s\n' "${WAYLAND_DISPLAY:-unset}"

    section "Kernel headers"
    if [[ -e "/lib/modules/$(uname -r)/build/Makefile" ]]; then
        printf 'Matching headers: present\n'
        readlink -f "/lib/modules/$(uname -r)/build" || true
    else
        printf 'Matching headers: MISSING\n'
    fi

    command_output "AOC USB device" lsusb -v -d "$USB_ID"
    command_output "All DisplayLink USB devices" bash -c "lsusb | grep -i -E '17e9|displaylink|aoc' || true"
    command_output "DKMS status" dkms status
    command_output "EVDI module information" modinfo evdi
    command_output "Loaded EVDI module" bash -c "lsmod | grep -E '^evdi|^drm' || true"
    command_output "EVDI sysfs" bash -c "for f in /sys/devices/evdi/version /sys/devices/evdi/count; do [ -r \"\$f\" ] && echo \"\$f: \$(cat \"\$f\")\"; done"

    section "DRM connectors"
    for connector in /sys/class/drm/card*-*; do
        [[ -e "$connector" ]] || continue
        printf '\n%s\n' "$connector"
        printf '  status: %s\n' "$(cat "$connector/status" 2>/dev/null || echo unknown)"
        printf '  enabled: %s\n' "$(cat "$connector/enabled" 2>/dev/null || echo unknown)"
        printf '  modes: '
        tr '\n' ' ' < "$connector/modes" 2>/dev/null || true
        printf '\n'
        printf '  driver: %s\n' "$(basename "$(readlink -f "$connector/device/driver" 2>/dev/null || echo unknown)")"
    done

    command_output "DisplayLink service status" systemctl --no-pager --full status aoc-i1659fwux-displaylink.service
    command_output "DisplayLink service journal" journalctl -b --no-pager -u aoc-i1659fwux-displaylink.service -n 150
    command_output "Recent EVDI/DisplayLink kernel messages" bash -c "dmesg 2>/dev/null | grep -i -E 'evdi|displaylink|17e9|ff10|usb [0-9].*error|drm' | tail -n 250 || true"

    if [[ -n "${DISPLAY:-}" ]] && command -v xrandr >/dev/null 2>&1; then
        command_output "Xrandr providers" xrandr --listproviders
        command_output "Xrandr outputs" xrandr --query
        command_output "Xrandr properties" xrandr --props
    else
        section "Xrandr"
        printf 'Not collected because DISPLAY is unset or xrandr is unavailable.\n'
    fi

    section "Package-owned configuration"
    for file in \
        /etc/systemd/system/aoc-i1659fwux-displaylink.service \
        /etc/modprobe.d/aoc-i1659fwux-evdi.conf \
        /etc/modules-load.d/aoc-i1659fwux-evdi.conf \
        /etc/udev/rules.d/85-aoc-i1659fwux-displaylink.rules \
        /var/lib/aoc-i1659fwux-displaylink/install-state; do
        printf '\n--- %s ---\n' "$file"
        if [[ -r "$file" ]]; then
            cat "$file"
        else
            printf 'not present or not readable\n'
        fi
    done
} > "$OUTPUT_FILE"

printf 'Diagnostics saved to: %s\n' "$OUTPUT_FILE"
AOC_DIAGNOSTICS_PAYLOAD_EOF
}

write_resolution_payload() {
    cat <<'AOC_RESOLUTION_PAYLOAD_EOF'
#!/usr/bin/env bash
set -u
IFS=$'\n\t'

USB_ID="17e9:ff10"
TARGET_MODE="1920x1080"
CUSTOM_MODE="AOC-I1659FWUX-1920x1080-60"
QUIET=0
DRY_RUN=0
WAIT_SECONDS=0
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
LOG_FILE="$LOG_DIR/aoc-i1659fwux-resolution.log"

usage() {
    cat <<'HELP'
Usage: aoc-i1659fwux-resolution [--quiet] [--dry-run] [--wait SECONDS]

Checks only the EVDI output associated with an attached AOC I1659FWUX and sets
1920x1080 when the monitor is connected at an incompatible resolution. It does
not change primary-display, position, rotation, mirroring, HDMI, or login settings.

Options:
  --quiet         Write only to the per-user cache log.
  --dry-run       Report the xrandr command without applying it.
  --wait SECONDS  Wait for the EVDI X11 connector to appear after login.
HELP
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet)
            QUIET=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --wait)
            [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || {
                printf '%s\n' "--wait requires a non-negative number of seconds." >&2
                exit 2
            }
            WAIT_SECONDS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

mkdir -p "$LOG_DIR" 2>/dev/null || true

say() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true
    if (( QUIET == 0 )); then
        printf '%s\n' "$*"
    fi
}

run() {
    if (( DRY_RUN == 1 )); then
        say "Would run: $*"
        return 0
    fi
    "$@"
}

if [[ -z "${DISPLAY:-}" ]]; then
    say "No graphical DISPLAY is available; no resolution change was attempted."
    exit 0
fi

if ! command -v xrandr >/dev/null 2>&1; then
    say "xrandr is unavailable; no resolution change was attempted."
    exit 0
fi

session_type="${XDG_SESSION_TYPE:-}"
if [[ -z "$session_type" && -n "${XDG_SESSION_ID:-}" ]] && command -v loginctl >/dev/null 2>&1; then
    session_type="$(loginctl show-session "$XDG_SESSION_ID" -p Type --value 2>/dev/null || true)"
fi
if [[ "$session_type" == "wayland" ]]; then
    say "Wayland session detected. This helper does not change compositor settings; the driver remains installed without forcing a session change."
    exit 0
fi

if command -v lsusb >/dev/null 2>&1 && ! lsusb -d "$USB_ID" >/dev/null 2>&1; then
    say "AOC I1659FWUX USB device $USB_ID is not connected."
    exit 0
fi

find_evdi_output() {
    local drm_path driver_path connector candidate
    local -a connected_outputs=()

    mapfile -t connected_outputs < <(xrandr --query 2>/dev/null | awk '$2=="connected" {print $1}')
    (( ${#connected_outputs[@]} > 0 )) || return 1

    for drm_path in /sys/class/drm/card*-*; do
        [[ -d "$drm_path" ]] || continue
        [[ "$(cat "$drm_path/status" 2>/dev/null || true)" == "connected" ]] || continue

        driver_path="$(readlink -f "$drm_path/device/driver" 2>/dev/null || true)"
        [[ "$(basename "$driver_path")" == "evdi" ]] || continue

        connector="$(basename "$drm_path")"
        connector="${connector#card*-}"
        for candidate in "${connected_outputs[@]}"; do
            if [[ "$candidate" == "$connector" || "$candidate" == "$connector"-* ]]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
    done

    # Older Xorg stacks may not preserve the DRM connector name. Restrict the
    # fallback to names historically used only for EVDI/DisplayLink outputs.
    for candidate in "${connected_outputs[@]}"; do
        if [[ "$candidate" == DVI-I-* || "$candidate" == DisplayLink-* ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

output=""
deadline=$((SECONDS + WAIT_SECONDS))
while :; do
    output="$(find_evdi_output || true)"
    [[ -n "$output" ]] && break

    if (( SECONDS >= deadline )); then
        say "No connected EVDI/DisplayLink X11 output was identified; no other output was changed."
        exit 0
    fi
    sleep 1
done

current_line="$(xrandr --query 2>/dev/null | awk -v out="$output" '$1==out && $2=="connected" {print; exit}')"
if [[ "$current_line" == *"${TARGET_MODE}+"* ]]; then
    say "$output is already using $TARGET_MODE; no change was needed."
    exit 0
fi

if xrandr --query 2>/dev/null | awk -v out="$output" -v mode="$TARGET_MODE" '
    $1==out && $2=="connected" {inside=1; next}
    inside && $1 !~ /^[0-9]/ {inside=0}
    inside && $1==mode {found=1}
    END {exit !found}
'; then
    if run xrandr --output "$output" --mode "$TARGET_MODE"; then
        say "Set only $output to $TARGET_MODE using the monitor-provided mode."
        exit 0
    fi
fi

# CVT 1920x1080 at 60 Hz. This mode is added only to the identified EVDI output.
modeline=(173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync)

if ! xrandr --query 2>/dev/null | grep -Fq "$CUSTOM_MODE"; then
    run xrandr --newmode "$CUSTOM_MODE" "${modeline[@]}" || {
        say "Could not create a 1920x1080 mode; no display settings were changed."
        exit 0
    }
fi

run xrandr --addmode "$output" "$CUSTOM_MODE" || {
    say "Could not add the custom mode to $output; no other output was changed."
    exit 0
}

if run xrandr --output "$output" --mode "$CUSTOM_MODE"; then
    say "Corrected only $output to 1920x1080 at 60 Hz."
else
    say "The monitor rejected the custom mode; no other output was changed."
fi
AOC_RESOLUTION_PAYLOAD_EOF
}

usage() {
    cat <<USAGE
$PROJECT_NAME single-file installer v$PROJECT_VERSION

Usage:
  ./$(basename "$SCRIPT_PATH") --validate
  ./$(basename "$SCRIPT_PATH") --preflight
  sudo ./$(basename "$SCRIPT_PATH") [installation options]
  ./$(basename "$SCRIPT_PATH") --diagnostics [OUTPUT_FILE]
  sudo ./$(basename "$SCRIPT_PATH") --uninstall
  sudo ./$(basename "$SCRIPT_PATH") --rollback

Installation options:
  --accept-displaylink-eula   Confirm acceptance of the Synaptics DisplayLink EULA.
  --driver-zip PATH           Use a previously downloaded official DisplayLink 6.3 ZIP.
  --no-resolution-helper     Do not install the post-login 1920x1080 correction helper.
  --force-unsupported-kernel Continue when the kernel is outside the verified 4.15-6.15 range.
  --keep-download            Keep the downloaded official ZIP beside this script.
  -h, --help                 Show this help.

The ZIP package contains only this Bash file. Its built-in modes provide
validation, preflight, installation, diagnostics, automatic rollback, and
uninstallation.

This installer intentionally does not modify login-manager, autologin, PAM,
Wayland/X11 selection, Xorg configuration, HDMI settings, desktop layout,
or Raspberry Pi boot display settings.
USAGE
}

log() {
    local msg="$*" line
    line="[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
    printf '%s\n' "$line"
    if (( LOG_ACTIVE == 1 )); then
        printf '%s\n' "$line" >> "$LOG_FILE"
    fi
}

warn() {
    log "WARNING: $*"
}

die() {
    log "ERROR: $*"
    if (( INSTALL_STARTED == 1 )); then
        rollback_install 1
    fi
    exit 1
}

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        die "Run this installer with sudo: sudo ./$(basename "$SCRIPT_PATH")"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --accept-displaylink-eula)
                ACCEPT_EULA=1
                shift
                ;;
            --driver-zip)
                [[ $# -ge 2 ]] || die "--driver-zip requires a path."
                OFFLINE_ZIP="$2"
                shift 2
                ;;
            --no-resolution-helper)
                ENABLE_RESOLUTION_HELPER=0
                shift
                ;;
            --force-unsupported-kernel)
                FORCE_UNSUPPORTED_KERNEL=1
                shift
                ;;
            --keep-download)
                KEEP_DOWNLOAD=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done
}

version_to_int() {
    local major minor
    major="${1%%.*}"
    minor="${1#*.}"
    minor="${minor%%.*}"
    printf '%d\n' "$((10#$major * 1000 + 10#$minor))"
}

check_platform() {
    local arch model os_id kernel_mm kernel_int
    arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    case "$arch" in
        arm64|aarch64) ;;
        *) die "This package is for 64-bit ARM only. Detected architecture: $arch" ;;
    esac

    if [[ -r /proc/device-tree/model ]]; then
        model="$(tr -d '\0' </proc/device-tree/model)"
    else
        model=""
    fi
    if [[ "$model" != *"Raspberry Pi 4"* && "$model" != *"Raspberry Pi 5"* ]]; then
        die "This build targets Raspberry Pi 4 or Raspberry Pi 5 hardware. Detected: ${model:-unknown hardware}"
    fi

    os_id="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-unknown}")"
    case "$os_id" in
        raspbian|debian) ;;
        *) warn "Detected OS ID '$os_id'. This project is designed for 64-bit Raspberry Pi OS/Raspbian." ;;
    esac

    kernel_mm="$(uname -r | grep -oE '^[0-9]+\.[0-9]+' || true)"
    [[ -n "$kernel_mm" ]] || die "Could not determine the running kernel version."
    kernel_int="$(version_to_int "$kernel_mm")"
    if (( kernel_int < 4015 || kernel_int > 6015 )); then
        if (( FORCE_UNSUPPORTED_KERNEL == 0 )); then
            die "Kernel $kernel_mm is outside the official DisplayLink 6.3 verified range (4.15-6.15). Re-run with --force-unsupported-kernel only if you accept the risk."
        fi
        warn "Continuing on unverified kernel $kernel_mm because --force-unsupported-kernel was supplied."
    fi

    log "Platform check passed: ${model:-Raspberry Pi 4/5}, architecture $arch, kernel $(uname -r)."
}

check_for_conflicts() {
    local conflicts=()

    if [[ -e /opt/displaylink ]]; then
        conflicts+=("/opt/displaylink")
    fi
    for existing_path in \
        /usr/lib/displaylink \
        /usr/libexec/displaylink \
        /usr/share/displaylink \
        /usr/share/displaylink-driver \
        /etc/udev/rules.d/99-displaylink.rules \
        /etc/modprobe.d/evdi.conf \
        /etc/modules-load.d/evdi.conf \
        /lib/systemd/system/displaylink-driver.service \
        /usr/lib/systemd/system/displaylink-driver.service; do
        if [[ -e "$existing_path" ]]; then
            conflicts+=("$existing_path")
        fi
    done
    if dpkg-query -W -f='${Status}' displaylink-driver 2>/dev/null | grep -q 'install ok installed'; then
        conflicts+=("APT package displaylink-driver")
    fi
    if systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -Eq '^(displaylink-driver|displaylink|dlm)\.service$'; then
        conflicts+=("an existing DisplayLink system service")
    fi
    if command -v dkms >/dev/null 2>&1 && dkms status 2>/dev/null | grep -qE '^evdi[/, ]'; then
        conflicts+=("an existing EVDI DKMS module")
    fi
    if lsmod 2>/dev/null | awk '{print $1}' | grep -qx evdi; then
        conflicts+=("an already-loaded EVDI kernel module")
    fi
    if compgen -G '/usr/src/evdi-*' >/dev/null; then
        conflicts+=("existing EVDI source under /usr/src")
    fi
    if [[ -e "$INSTALL_ROOT" || -e "$STATE_DIR" || -e "$SERVICE_FILE" || -e "$MANAGER_HELPER" ]]; then
        conflicts+=("an existing installation of this AOC package")
    fi

    if (( ${#conflicts[@]} > 0 )); then
        printf '\nConflicting DisplayLink installation detected:\n'
        printf '  - %s\n' "${conflicts[@]}"
        cat <<'MSG'

No files were changed. Remove the existing DisplayLink installation using its own
uninstaller before running this package. This installer will not automatically
remove or overwrite another driver's files because doing so could alter unrelated
system behavior.
MSG
        exit 2
    fi
}

apt_install_minimal() {
    local packages=(
        ca-certificates
        curl
        unzip
        dkms
        build-essential
        binutils
        libdrm-dev
        libusb-1.0-0
        pkg-config
        x11-xserver-utils
        usbutils
    )
    local missing=()
    local pkg

    for pkg in "${packages[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
            missing+=("$pkg")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        log "Installing only required packages: ${missing[*]}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y --no-install-recommends "${missing[@]}"
    else
        log "Required user-space dependencies are already installed."
    fi
}

ensure_kernel_headers() {
    local kver="$(uname -r)"
    local candidates=("linux-headers-$kver" raspberrypi-kernel-headers linux-headers-rpi-v8)
    local pkg

    if [[ -e "/lib/modules/$kver/build/Makefile" ]]; then
        log "Matching kernel headers are already present for $kver."
        return
    fi

    log "Matching kernel headers are missing; searching Raspberry Pi OS packages."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    for pkg in "${candidates[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            log "Trying kernel-header package: $pkg"
            if apt-get install -y --no-install-recommends "$pkg"; then
                break
            fi
        fi
    done

    if [[ ! -e "/lib/modules/$kver/build/Makefile" ]]; then
        die "Headers matching the running kernel $kver are unavailable. No driver files were installed. Update/reboot into the matching Raspberry Pi OS kernel, then run this installer again."
    fi

    log "Matching kernel headers are available for $kver."
}

confirm_eula() {
    if (( ACCEPT_EULA == 1 )); then
        return
    fi

    if [[ ! -t 0 ]]; then
        die "DisplayLink EULA acceptance is required. Re-run with --accept-displaylink-eula after reviewing: $DISPLAYLINK_EULA_URL"
    fi

    printf '\nThe proprietary DisplayLink user-space driver is governed by the Synaptics EULA:\n%s\n\n' "$DISPLAYLINK_EULA_URL"
    read -r -p "Type AGREE to confirm that you reviewed and accept the EULA: " answer
    [[ "$answer" == "AGREE" ]] || die "EULA not accepted; installation cancelled."
    ACCEPT_EULA=1
}

obtain_driver_zip() {
    local destination="$WORK_DIR/displaylink-${DISPLAYLINK_VERSION}.zip"

    # The EULA governs the proprietary user-space payload whether it is
    # downloaded now or supplied as an already-downloaded official ZIP.
    confirm_eula

    if [[ -n "$OFFLINE_ZIP" ]]; then
        [[ -f "$OFFLINE_ZIP" ]] || die "Official driver ZIP not found: $OFFLINE_ZIP"
        cp -- "$OFFLINE_ZIP" "$destination"
        log "Using supplied official DisplayLink ZIP: $OFFLINE_ZIP"
    else
        log "Downloading the official unmodified DisplayLink $DISPLAYLINK_VERSION ZIP from Synaptics."
        curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --output "$destination" "$DISPLAYLINK_ZIP_URL"
    fi

    unzip -tq "$destination" >/dev/null || die "The downloaded DisplayLink ZIP failed its integrity test."

    if (( KEEP_DOWNLOAD == 1 )); then
        cp -- "$destination" "$SCRIPT_DIR/DisplayLink-USB-Graphics-Software-for-Ubuntu-${DISPLAYLINK_VERSION}.zip"
        log "Kept a copy of the official ZIP in the project directory."
    fi

    DRIVER_ZIP="$destination"
}

extract_official_payload() {
    local zip_file="$1"
    local zip_dir="$WORK_DIR/zip"
    local payload_dir="$WORK_DIR/payload"
    local run_file extracted_root

    mkdir -p "$zip_dir" "$payload_dir"
    unzip -q "$zip_file" -d "$zip_dir"
    run_file="$(find "$zip_dir" -type f -name 'displaylink-driver-6.3*.run' -print -quit)"
    [[ -n "$run_file" ]] || die "The ZIP did not contain the expected official DisplayLink 6.3 .run installer."
    chmod +x "$run_file"

    log "Extracting official driver components without executing the Ubuntu installer."
    (
        cd "$payload_dir"
        "$run_file" --noexec --keep --target "$(basename "${run_file%.run}")" >/dev/null
    )

    extracted_root="$(find "$payload_dir" -mindepth 1 -maxdepth 2 -type f -name DisplayLinkManager -printf '%h\n' | grep -E '/(aarch64|arm64)[^/]*/?$' | head -n1 || true)"
    if [[ -z "$extracted_root" ]]; then
        extracted_root="$(find "$payload_dir" -type f -name DisplayLinkManager -path '*aarch64*' -printf '%h\n' | head -n1 || true)"
    fi
    [[ -n "$extracted_root" ]] || die "No aarch64 DisplayLinkManager binary was found in the official payload."

    PAYLOAD_DIR="$payload_dir"
}

install_evdi_dkms() {
    local payload_dir="$1"
    local evdi_archive evdi_extract dkms_conf module_src package_name evdi_root

    evdi_archive="$(find "$payload_dir" -type f \( -iname 'evdi*src*.tar.gz' -o -iname 'evdi*.tar.gz' \) -print -quit)"
    [[ -n "$evdi_archive" ]] || die "No EVDI source archive was found in the official payload."

    evdi_extract="$WORK_DIR/evdi-source"
    mkdir -p "$evdi_extract"
    tar -xzf "$evdi_archive" -C "$evdi_extract"

    dkms_conf="$(find "$evdi_extract" -type f -name dkms.conf -print -quit)"
    [[ -n "$dkms_conf" ]] || die "The EVDI source did not contain dkms.conf."

    EVDI_VERSION="$(sed -nE 's/^[[:space:]]*PACKAGE_VERSION=["'"']?([^"'"'[:space:]]+).*/\1/p' "$dkms_conf" | head -n1)"
    package_name="$(sed -nE 's/^[[:space:]]*PACKAGE_NAME=["'"']?([^"'"'[:space:]]+).*/\1/p' "$dkms_conf" | head -n1)"
    [[ -n "$EVDI_VERSION" ]] || die "Could not determine the bundled EVDI version."
    [[ "$package_name" == "evdi" ]] || die "Unexpected DKMS package name: ${package_name:-unknown}"

    if dkms status 2>/dev/null | grep -qE '^evdi[/, ]'; then
        die "An EVDI DKMS module is already installed. This installer will not overwrite it."
    fi

    module_src="$(dirname "$dkms_conf")"
    evdi_root="$(dirname "$module_src")"
    if [[ ! -f "$evdi_root/library/Makefile" ]]; then
        evdi_root="$(find "$evdi_extract" -type f -path '*/library/Makefile' -printf '%h\n' -quit | xargs -r dirname)"
    fi
    [[ -n "$evdi_root" && -f "$evdi_root/library/Makefile" ]] || die "The EVDI source did not contain the libevdi build files."
    EVDI_SOURCE_ROOT="$evdi_root"

    mkdir -p "/usr/src/evdi-$EVDI_VERSION"
    cp -a "$module_src"/. "/usr/src/evdi-$EVDI_VERSION/"
    printf '%s\n' "$PROJECT_NAME $PROJECT_VERSION" > "/usr/src/evdi-$EVDI_VERSION/.aoc-i1659fwux-owned"

    log "Building EVDI $EVDI_VERSION for kernel $(uname -r) with DKMS."
    dkms add -m evdi -v "$EVDI_VERSION"
    dkms build -m evdi -v "$EVDI_VERSION" -k "$(uname -r)"
    dkms install -m evdi -v "$EVDI_VERSION" -k "$(uname -r)"

    modinfo evdi >/dev/null 2>&1 || die "EVDI installed but modinfo could not find the module."
}

install_displaylink_userspace() {
    local payload_dir="$1"
    local manager manager_dir file dependency_report

    manager="$(find "$payload_dir" -type f -name DisplayLinkManager -path '*aarch64*' -print -quit)"
    [[ -n "$manager" ]] || die "No aarch64 DisplayLinkManager binary was found."
    manager_dir="$(dirname "$manager")"

    if ! readelf -h "$manager" 2>/dev/null | grep -qE 'Machine:[[:space:]]+AArch64'; then
        die "The selected DisplayLinkManager is not an AArch64 executable."
    fi

    mkdir -p "$INSTALL_ROOT"
    install -m 0755 "$manager" "$INSTALL_ROOT/DisplayLinkManager"

    # Build the userspace library from the exact EVDI source bundled with the
    # official driver. This keeps the kernel module and libevdi ABI matched.
    log "Building libevdi $EVDI_VERSION from the official bundled source."
    make -C "$EVDI_SOURCE_ROOT/library" clean >/dev/null
    make -C "$EVDI_SOURCE_ROOT/library"
    while IFS= read -r -d '' file; do
        cp -a "$file" "$INSTALL_ROOT/"
    done < <(find "$EVDI_SOURCE_ROOT/library" -maxdepth 1 \( -type f -o -type l \) -name 'libevdi.so*' -print0)
    compgen -G "$INSTALL_ROOT/libevdi.so*" >/dev/null || die "libevdi built but no library files were produced."

    # Use Raspberry Pi OS's maintained libusb runtime instead of installing the
    # bundled Ubuntu copy. Copy only any other architecture-local libraries.
    while IFS= read -r -d '' file; do
        case "$(basename "$file")" in
            libevdi.so*|libusb-1.0.so*) continue ;;
        esac
        cp -a "$file" "$INSTALL_ROOT/"
    done < <(find "$manager_dir" -maxdepth 1 \( -type f -o -type l \) \( -name '*.so' -o -name '*.so.*' \) -print0)

    while IFS= read -r -d '' file; do
        cp -a "$file" "$INSTALL_ROOT/"
    done < <(find "$payload_dir" -type f -name '*.spkg' -print0)
    compgen -G "$INSTALL_ROOT/*.spkg" >/dev/null || die "No DisplayLink firmware package was found in the official payload."

    file="$(find "$payload_dir" -type f -iname 'LICENSE*' -print -quit || true)"
    if [[ -n "$file" ]]; then
        cp -a "$file" "$INSTALL_ROOT/DisplayLink-LICENSE"
    fi

    chmod 0755 "$INSTALL_ROOT/DisplayLinkManager"

    dependency_report="$(LD_LIBRARY_PATH="$INSTALL_ROOT" ldd "$INSTALL_ROOT/DisplayLinkManager" 2>&1 || true)"
    if grep -q 'not found' <<<"$dependency_report"; then
        printf '%s\n' "$dependency_report" | tee -a "$LOG_FILE"
        die "DisplayLinkManager has unresolved runtime-library dependencies."
    fi

    log "Installed the official unmodified aarch64 DisplayLink manager, matched libevdi, and firmware under $INSTALL_ROOT."
}

write_driver_configuration() {
    local module pre_list="" usb_device
    local -a pre_modules=()

    cat > "$MODPROBE_FILE" <<'CONF'
# Added by the AOC I1659FWUX Raspberry Pi 4/5 DisplayLink package.
# One virtual device is sufficient for this single-monitor package.
options evdi initial_device_count=1
CONF

    # Order only DRM modules that actually exist on this system ahead of EVDI.
    # This avoids introducing a dependency on a Raspberry Pi graphics module
    # that the user's current boot/display configuration does not use.
    for module in drm_kms_helper vc4; do
        if modinfo "$module" >/dev/null 2>&1; then
            pre_modules+=("$module")
        fi
    done
    if (( ${#pre_modules[@]} > 0 )); then
        printf -v pre_list '%s ' "${pre_modules[@]}"
        pre_list="${pre_list% }"
        printf 'softdep evdi pre: %s\n' "$pre_list" >> "$MODPROBE_FILE"
    fi

    printf 'evdi\n' > "$MODULES_LOAD_FILE"

    cat > "$UDEV_RULE_FILE" <<'RULE'
# AOC I1659FWUX (DisplayLink USB ID 17e9:ff10): prevent USB autosuspend only for this monitor.
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="17e9", ATTR{idProduct}=="ff10", TEST=="power/control", ATTR{power/control}="on"
RULE

    cat > "$SERVICE_FILE" <<EOF_SERVICE
[Unit]
Description=AOC I1659FWUX DisplayLink Manager
Documentation=$DISPLAYLINK_EULA_URL
After=systemd-modules-load.service
Wants=systemd-modules-load.service
ConditionPathExists=$INSTALL_ROOT/DisplayLinkManager

[Service]
Type=simple
WorkingDirectory=$INSTALL_ROOT
Environment=LD_LIBRARY_PATH=$INSTALL_ROOT
ExecStartPre=/sbin/modprobe evdi
ExecStart=$INSTALL_ROOT/DisplayLinkManager
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_SERVICE

    systemctl daemon-reload
    udevadm control --reload-rules

    # Apply the same exact-device power setting immediately when the monitor is
    # already connected; no other USB device is touched.
    for usb_device in /sys/bus/usb/devices/*; do
        [[ -r "$usb_device/idVendor" && -r "$usb_device/idProduct" ]] || continue
        [[ "$(cat "$usb_device/idVendor")" == "17e9" ]] || continue
        [[ "$(cat "$usb_device/idProduct")" == "ff10" ]] || continue
        [[ -w "$usb_device/power/control" ]] && printf 'on\n' > "$usb_device/power/control"
    done

    log "Added only monitor-specific module, USB, and service configuration."
}

install_helpers() {
    umask 022
    write_diagnostics_payload > "$DIAGNOSTICS_HELPER"
    chmod 0755 "$DIAGNOSTICS_HELPER"

    if (( ENABLE_RESOLUTION_HELPER == 1 )); then
        write_resolution_payload > "$RESOLUTION_HELPER"
        chmod 0755 "$RESOLUTION_HELPER"
        mkdir -p "$(dirname "$AUTOSTART_FILE")"
        cat > "$AUTOSTART_FILE" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=AOC I1659FWUX Resolution Check
Comment=Correct only the AOC DisplayLink output to 1920x1080 when needed
Exec=/usr/local/bin/aoc-i1659fwux-resolution --quiet --wait 30
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESKTOP
        log "Installed a post-login resolution helper limited to the EVDI output for USB device $AOC_USB_ID."
    else
        log "Resolution helper was disabled by request."
    fi
}

write_state() {
    local source_sha
    mkdir -p "$STATE_DIR"
    source_sha="$(sha256sum "$SCRIPT_PATH" | awk '{print $1}')"
    cat > "$STATE_DIR/install-state" <<EOF_STATE
PROJECT_VERSION=$PROJECT_VERSION
DISPLAYLINK_VERSION=$DISPLAYLINK_VERSION
EVDI_VERSION=$EVDI_VERSION
KERNEL_VERSION=$(uname -r)
RESOLUTION_HELPER=$ENABLE_RESOLUTION_HELPER
INSTALLER_SHA256=$source_sha
INSTALLED_AT=$(date --iso-8601=seconds)
EOF_STATE

    install -m 0755 "$SCRIPT_PATH" "$STATE_DIR/aoc-i1659fwux-driver.sh"
    install -m 0755 "$SCRIPT_PATH" "$MANAGER_HELPER"
}

start_driver() {
    systemctl enable aoc-i1659fwux-displaylink.service
    modprobe -r evdi 2>/dev/null || true
    modprobe evdi
    systemctl restart aoc-i1659fwux-displaylink.service

    sleep 2
    if systemctl is-active --quiet aoc-i1659fwux-displaylink.service; then
        log "DisplayLink service is active."
    else
        systemctl --no-pager --full status aoc-i1659fwux-displaylink.service | tee -a "$LOG_FILE" || true
        die "The DisplayLink service did not start. Run aoc-i1659fwux-diagnostics and review the generated report."
    fi
}

rollback_install() {
    local status="${1:-1}"
    if (( status == 0 || INSTALL_STARTED == 0 )); then
        exit "$status"
    fi

    trap - ERR
    set +e
    printf '\nInstallation failed. Rolling back files created by this run...\n' | tee -a "$LOG_FILE"
    systemctl disable --now aoc-i1659fwux-displaylink.service >/dev/null 2>&1
    rm -f "$SERVICE_FILE" "$MODPROBE_FILE" "$MODULES_LOAD_FILE" "$UDEV_RULE_FILE" "$RESOLUTION_HELPER" "$DIAGNOSTICS_HELPER" "$AUTOSTART_FILE" "$MANAGER_HELPER"
    rm -rf "$INSTALL_ROOT" "$STATE_DIR"
    if [[ -n "$EVDI_VERSION" ]]; then
        dkms remove -m evdi -v "$EVDI_VERSION" --all >/dev/null 2>&1
        if [[ -f "/usr/src/evdi-$EVDI_VERSION/.aoc-i1659fwux-owned" ]]; then
            rm -rf "/usr/src/evdi-$EVDI_VERSION"
        fi
    fi
    systemctl daemon-reload >/dev/null 2>&1
    udevadm control --reload-rules >/dev/null 2>&1
    printf 'Rollback completed. Required APT packages were intentionally left installed.\n' | tee -a "$LOG_FILE"
    exit "$status"
}

install_main() {
    parse_args "$@"
    require_root

    log "Checking platform and existing driver state for $PROJECT_NAME v$PROJECT_VERSION."
    check_platform
    check_for_conflicts
    confirm_eula

    touch "$LOG_FILE"
    chmod 0644 "$LOG_FILE"
    LOG_ACTIVE=1
    trap 'rollback_install $?' ERR
    log "Preflight checks passed; beginning installation."

    apt_install_minimal
    ensure_kernel_headers

    WORK_DIR="$(mktemp -d /tmp/aoc-i1659fwux-install.XXXXXX)"
    trap 'rm -rf "$WORK_DIR"' EXIT

    obtain_driver_zip
    extract_official_payload "$DRIVER_ZIP"

    INSTALL_STARTED=1
    install_evdi_dkms "$PAYLOAD_DIR"
    install_displaylink_userspace "$PAYLOAD_DIR"
    write_driver_configuration
    install_helpers
    write_state
    start_driver

    trap - ERR
    rm -rf "$WORK_DIR"
    trap - EXIT

    cat <<EOF_DONE

Installation completed successfully.

Installed:
  - Official DisplayLink $DISPLAYLINK_VERSION aarch64 manager
  - EVDI $EVDI_VERSION DKMS module and matching locally built libevdi
  - AOC I1659FWUX USB rule for device $AOC_USB_ID
  - A monitor-specific service and diagnostics command
  - 1920x1080 post-login correction helper: $([[ $ENABLE_RESOLUTION_HELPER -eq 1 ]] && echo enabled || echo disabled)

Not changed:
  - Login manager, autologin, PAM, greeter, or login-screen configuration
  - Wayland/X11 session selection
  - Xorg configuration
  - HDMI, boot display, desktop layout, primary-display, rotation, or mirroring settings

Connect the monitor directly to a Raspberry Pi 4 or Raspberry Pi 5 USB 3 port, then log out and back in
or reboot when convenient. The installer does not reboot automatically.

Diagnostics command:
  aoc-i1659fwux-diagnostics

Uninstall command:
  sudo $MANAGER_HELPER --uninstall
EOF_DONE
    log "Installation finished successfully."
}


run_temp_payload() {
    local writer="$1"
    shift
    local tmp status
    tmp="$(mktemp /tmp/aoc-i1659fwux-mode.XXXXXX)"
    "$writer" > "$tmp"
    chmod 0755 "$tmp"
    set +e
    "$tmp" "$@"
    status=$?
    set -e
    rm -f -- "$tmp"
    return "$status"
}

validate_self() {
    local failed=0 source="$SCRIPT_PATH" source_sha scan_file
    pass() { printf '[PASS] %s\n' "$*"; }
    fail() { printf '[FAIL] %s\n' "$*" >&2; failed=1; }

    [[ -f "$source" ]] && pass "Single installer file is present: $(basename "$source")" || fail "Installer file is missing."
    [[ -x "$source" ]] && pass "Installer is executable." || fail "Installer is not executable."

    if bash -n "$source"; then
        pass "Bash syntax is valid."
    else
        fail "Bash syntax validation failed."
    fi

    source_sha="$(sha256sum "$source" | awk '{print $1}')"
    pass "Installer SHA-256: $source_sha"

    scan_file="$(mktemp /tmp/aoc-i1659fwux-validation.XXXXXX)"
    awk '
        /^validate_self\(\) \{/ {skip=1}
        /^run_preflight\(\) \{/ {skip=0}
        !skip {print}
    ' "$source" > "$scan_file"

    local forbidden_write
    forbidden_write='(install|cp|mv|rm|ln|tee|sed[[:space:]]+-i|cat[[:space:]]+>)[^#\n]*(/etc/(lightdm|gdm|sddm|pam\.d|X11)|/boot|config\.txt|cmdline\.txt)'
    if grep -En "$forbidden_write" "$scan_file"; then
        fail "A forbidden login, Xorg, PAM, or boot write target was found."
    else
        pass "No forbidden login, Xorg, PAM, or boot write target."
    fi

    if grep -En 'apt-get[[:space:]]+(dist-upgrade|full-upgrade|upgrade)|rpi-update|raspi-config' "$scan_file"; then
        fail "A system upgrade or global Raspberry Pi configuration command was found."
    else
        pass "No system upgrade or global Raspberry Pi configuration command."
    fi

    if grep -En 'xrandr[^\n]*(--primary|--pos|--left-of|--right-of|--above|--below|--rotate|--reflect|--same-as)' "$scan_file"; then
        fail "The resolution code contains a layout, primary, rotation, or mirroring operation."
    else
        pass "Resolution code is limited to mode selection on the identified EVDI output."
    fi

    if grep -En '/etc/xdg/autostart/aoc-i1659fwux-resolution\.desktop|/etc/systemd/system/aoc-i1659fwux-displaylink\.service|/etc/modprobe\.d/aoc-i1659fwux-evdi\.conf|/etc/modules-load\.d/aoc-i1659fwux-evdi\.conf|/etc/udev/rules\.d/85-aoc-i1659fwux-displaylink\.rules' "$scan_file" >/dev/null; then
        pass "Expected monitor-specific system file paths are present."
    else
        fail "Expected monitor-specific system file paths are missing."
    fi

    rm -f -- "$scan_file"

    if (( failed != 0 )); then
        printf '\nSingle-file package validation failed.\n' >&2
        return 1
    fi
    printf '\nSingle-file package validation passed.\n'
}

run_preflight() {
    run_temp_payload write_preflight_payload "$@"
}

run_diagnostics() {
    run_temp_payload write_diagnostics_payload "$@"
}

run_resolution() {
    run_temp_payload write_resolution_payload "$@"
}

uninstall_driver() {
    local state_file="$STATE_DIR/install-state" evdi_version=""
    require_root

    if [[ -r "$state_file" ]]; then
        evdi_version="$(sed -n 's/^EVDI_VERSION=//p' "$state_file" | head -n1)"
    fi

    log "Removing only files owned by $PROJECT_NAME."
    systemctl disable --now aoc-i1659fwux-displaylink.service >/dev/null 2>&1 || true
    rm -f -- "$SERVICE_FILE"
    systemctl daemon-reload

    rm -f -- \
        "$MODPROBE_FILE" \
        "$MODULES_LOAD_FILE" \
        "$UDEV_RULE_FILE" \
        "$RESOLUTION_HELPER" \
        "$DIAGNOSTICS_HELPER" \
        "$AUTOSTART_FILE"
    udevadm control --reload-rules >/dev/null 2>&1 || true

    if [[ -n "$evdi_version" ]]; then
        if [[ -f "/usr/src/evdi-$evdi_version/.aoc-i1659fwux-owned" ]]; then
            log "Removing package-owned EVDI $evdi_version DKMS module."
            dkms remove -m evdi -v "$evdi_version" --all >/dev/null 2>&1 || true
            rm -rf -- "/usr/src/evdi-$evdi_version"
        else
            log "EVDI source ownership marker is absent; leaving EVDI files untouched."
        fi
    else
        log "No recorded EVDI version was found; leaving any EVDI installation untouched."
    fi

    rm -rf -- "$INSTALL_ROOT"
    rm -f -- "$LOG_FILE"

    if lsmod 2>/dev/null | awk '{print $1}' | grep -qx evdi; then
        modprobe -r evdi >/dev/null 2>&1 || log "EVDI is still in use and will unload at the next reboot."
    fi

    # Remove the installed manager copy last. Removing the currently executing
    # file is safe on Linux; the process already has it open.
    rm -f -- "$MANAGER_HELPER"
    rm -rf -- "$STATE_DIR"

    cat <<'DONE'

Uninstall/rollback completed.

Only this package's dedicated files and ownership-marked EVDI source were removed.
Shared APT packages were left installed because other software may use them.
Login, desktop-session, HDMI, boot, and unrelated display settings were not altered.
No automatic reboot was performed.
DONE
}

dispatch() {
    case "${1:-}" in
        --validate)
            shift
            [[ $# -eq 0 ]] || die "--validate does not accept additional arguments."
            validate_self
            ;;
        --preflight)
            shift
            run_preflight "$@"
            ;;
        --diagnostics)
            shift
            run_diagnostics "$@"
            ;;
        --resolution)
            shift
            run_resolution "$@"
            ;;
        --uninstall|--rollback)
            shift
            [[ $# -eq 0 ]] || die "Uninstall/rollback does not accept additional arguments."
            uninstall_driver
            ;;
        -h|--help)
            usage
            ;;
        *)
            install_main "$@"
            ;;
    esac
}

dispatch "$@"
