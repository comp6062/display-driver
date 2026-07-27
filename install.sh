#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 022

PACKAGE_NAME="aoc-i1659fwux-rpi-displaylink"
PACKAGE_VERSION="0.2.1"
DISPLAYLINK_RELEASE="6.3"
DISPLAYLINK_ZIP_SHA256="7269856c7527060c513215ce1b5a36fef074d8e89cab89bcab13df342acce098"
DISPLAYLINK_ZIP_URL="https://www.synaptics.com/sites/default/files/exe_files/2026-06/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.3-EXE.zip"
DISPLAYLINK_EULA_URL="https://www.synaptics.com/products/displaylink-usb-graphics-software-ubuntu-63?filetype=exe"
AOC_USB_VENDOR="17e9"
AOC_USB_PRODUCT="ff10"
AOC_USB_ID="${AOC_USB_VENDOR}:${AOC_USB_PRODUCT}"
STATE_DIR="/var/lib/${PACKAGE_NAME}"
LOG_DIR="/var/log/${PACKAGE_NAME}"
INSTALL_ROOT="/opt/displaylink"
SAFE_UNIT="aoc-i1659fwux-displaylink.service"
SAFE_UNIT_PATH="/etc/systemd/system/${SAFE_UNIT}"
UDEV_RULE_PATH="/etc/udev/rules.d/99-aoc-i1659fwux-displaylink.rules"
MODULE_LOAD_PATH="/etc/modules-load.d/aoc-i1659fwux-evdi.conf"
EVDI_MODPROBE_PATH="/etc/modprobe.d/evdi.conf"
BUNDLE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_VENDOR_ZIP="${BUNDLE_DIR}/vendor/DisplayLink-USB-Graphics-Software-for-Ubuntu-6.3.zip"

CHECK_ONLY=0
REINSTALL=0
FORCE_KERNEL=0
NO_START=0
WORK_DIR=""
LOG_FILE=""
EVDI_VERSION=""
EVDI_LIBRARY_DIR=""

PROTECTED_PATHS=(
  "/etc/lightdm"
  "/etc/gdm3"
  "/etc/sddm.conf"
  "/etc/sddm.conf.d"
  "/etc/pam.d"
  "/etc/ssh"
  "/etc/systemd/logind.conf"
  "/etc/systemd/system/default.target"
  "/etc/systemd/system/display-manager.service"
  "/etc/systemd/system/getty@tty1.service.d"
  "/etc/systemd/system/getty@tty7.service.d"
  "/boot/config.txt"
  "/boot/firmware/config.txt"
  "/etc/X11"
  "/usr/share/X11/xorg.conf.d"
  "/etc/xdg/labwc"
  "/etc/xdg/wayfire.ini"
  "/etc/xdg/lxsession"
)

usage() {
  cat <<'USAGE'
Usage: sudo ./install.sh [options]

Options:
  --check-only                 Run platform checks without changing the system.
  --reinstall                  Remove this package's existing installation first.
  --force-unsupported-kernel   Continue outside the conservative 4.15-6.15 range.
  --no-start                   Install but do not start the driver in this boot.
  -h, --help                   Show this help.
USAGE
}

log() {
  printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"
}

warn() {
  log "WARNING: $*" >&2
}

die() {
  log "ERROR: $*" >&2
  return 1
}

version_lt() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" != "$2" ]]
}

version_gt() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" != "$2" ]]
}

cleanup_workdir() {
  if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
    rm -rf -- "${WORK_DIR}"
  fi
}

read_pi_model() {
  if [[ -r /proc/device-tree/model ]]; then
    tr -d '\0' < /proc/device-tree/model
  else
    printf 'unknown'
  fi
}

manifest_protected() {
  local root item
  for root in "${PROTECTED_PATHS[@]}"; do
    if [[ ! -e "$root" && ! -L "$root" ]]; then
      printf 'ABSENT|%s\n' "$root"
      continue
    fi

    if [[ -L "$root" ]]; then
      printf 'LINK|%s|%s\n' "$root" "$(readlink -- "$root")"
    elif [[ -f "$root" ]]; then
      printf 'FILE|%s|%s|%s\n' "$root" \
        "$(stat -c '%a:%u:%g:%s:%Y' -- "$root")" \
        "$(sha256sum -- "$root" | awk '{print $1}')"
    elif [[ -d "$root" ]]; then
      printf 'DIRROOT|%s|%s\n' "$root" "$(stat -c '%a:%u:%g:%Y' -- "$root")"
      while IFS= read -r -d '' item; do
        if [[ -L "$item" ]]; then
          printf 'LINK|%s|%s\n' "$item" "$(readlink -- "$item")"
        elif [[ -f "$item" ]]; then
          printf 'FILE|%s|%s|%s\n' "$item" \
            "$(stat -c '%a:%u:%g:%s:%Y' -- "$item")" \
            "$(sha256sum -- "$item" | awk '{print $1}')"
        elif [[ -d "$item" ]]; then
          printf 'DIR|%s|%s\n' "$item" "$(stat -c '%a:%u:%g:%Y' -- "$item")"
        else
          printf 'OTHER|%s|%s\n' "$item" "$(stat -c '%F:%a:%u:%g:%s:%Y' -- "$item")"
        fi
      done < <(find -P "$root" -mindepth 1 -xdev -print0 | sort -z)
    fi
  done
}

snapshot_protected() {
  local snapshot_tmp="${STATE_DIR}/protected.tmp"
  local snapshot_final="${STATE_DIR}/protected"
  rm -rf -- "$snapshot_tmp" "$snapshot_final"
  install -d -m 0700 "$snapshot_tmp"
  : > "${snapshot_tmp}/present.list"
  : > "${snapshot_tmp}/absent.list"

  local path
  for path in "${PROTECTED_PATHS[@]}"; do
    if [[ -e "$path" || -L "$path" ]]; then
      printf '%s\n' "${path#/}" >> "${snapshot_tmp}/present.list"
    else
      printf '%s\n' "$path" >> "${snapshot_tmp}/absent.list"
    fi
  done

  if [[ -s "${snapshot_tmp}/present.list" ]]; then
    tar -C / -cpf "${snapshot_tmp}/protected-before.tar" \
      -T "${snapshot_tmp}/present.list"
  else
    : > "${snapshot_tmp}/protected-before.tar"
  fi

  manifest_protected > "${snapshot_tmp}/manifest-before.txt"
  chmod 0600 "${snapshot_tmp}/protected-before.tar" \
    "${snapshot_tmp}/manifest-before.txt" \
    "${snapshot_tmp}/present.list" \
    "${snapshot_tmp}/absent.list"
  touch "${snapshot_tmp}/READY"
  chmod 0600 "${snapshot_tmp}/READY"
  mv -- "$snapshot_tmp" "$snapshot_final"
}

restore_protected() {
  [[ -f "${STATE_DIR}/protected/READY" ]] || return 0

  local path
  if [[ -f "${STATE_DIR}/protected/present.list" ]]; then
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      rm -rf -- "/$path"
    done < "${STATE_DIR}/protected/present.list"
  fi

  if [[ -f "${STATE_DIR}/protected/absent.list" ]]; then
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      rm -rf -- "$path"
    done < "${STATE_DIR}/protected/absent.list"
  fi

  if [[ -s "${STATE_DIR}/protected/protected-before.tar" ]]; then
    tar -C / -xpf "${STATE_DIR}/protected/protected-before.tar"
  fi
}

verify_and_restore_protected() {
  [[ -f "${STATE_DIR}/protected/READY" ]] \
    || die "Protected-path snapshot is incomplete; refusing to report success."
  manifest_protected > "${STATE_DIR}/protected/manifest-after.txt"
  chmod 0600 "${STATE_DIR}/protected/manifest-after.txt"
  if ! cmp -s "${STATE_DIR}/protected/manifest-before.txt" \
      "${STATE_DIR}/protected/manifest-after.txt"; then
    warn "A protected login, authentication, boot, X11, or desktop-session path changed during installation."
    warn "Restoring the protected paths exactly to their pre-install state."
    diff -u "${STATE_DIR}/protected/manifest-before.txt" \
      "${STATE_DIR}/protected/manifest-after.txt" \
      > "${STATE_DIR}/protected/differences-restored.diff" || true
    chmod 0600 "${STATE_DIR}/protected/differences-restored.diff"
    restore_protected
    manifest_protected > "${STATE_DIR}/protected/manifest-restored.txt"
    chmod 0600 "${STATE_DIR}/protected/manifest-restored.txt"
    cmp -s "${STATE_DIR}/protected/manifest-before.txt" \
      "${STATE_DIR}/protected/manifest-restored.txt" \
      || die "Protected system settings could not be restored. Backup: ${STATE_DIR}/protected"
  fi
}

snapshot_evdi_config() {
  mkdir -p "${STATE_DIR}/evdi-config"
  if [[ -e "${EVDI_MODPROBE_PATH}" || -L "${EVDI_MODPROBE_PATH}" ]]; then
    printf 'present\n' > "${STATE_DIR}/evdi-config/evdi.conf.state"
    cp -a -- "${EVDI_MODPROBE_PATH}" "${STATE_DIR}/evdi-config/evdi.conf.before"
  else
    printf 'absent\n' > "${STATE_DIR}/evdi-config/evdi.conf.state"
  fi
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

  udevadm control --reload-rules >/dev/null 2>&1 || true
  depmod -a >/dev/null 2>&1 || true
}

remove_partial_driver() {
  systemctl disable --now "${SAFE_UNIT}" >/dev/null 2>&1 || true
  rm -f -- "${SAFE_UNIT_PATH}"
  systemctl daemon-reload >/dev/null 2>&1 || true

  modprobe -r evdi >/dev/null 2>&1 || true

  if [[ -z "${EVDI_VERSION}" && -r "${STATE_DIR}/evdi-version" ]]; then
    EVDI_VERSION="$(cat "${STATE_DIR}/evdi-version")"
  fi
  if [[ -n "${EVDI_VERSION}" ]]; then
    if command -v dkms >/dev/null 2>&1; then
      if dkms remove -m evdi -v "${EVDI_VERSION}" --all >/dev/null 2>&1; then
        rm -rf -- "/usr/src/evdi-${EVDI_VERSION}"
      else
        warn "EVDI DKMS cleanup failed; preserving /usr/src/evdi-${EVDI_VERSION} for manual recovery."
      fi
    else
      warn "DKMS is unavailable; preserving /usr/src/evdi-${EVDI_VERSION} for manual recovery."
    fi
  fi

  rm -rf -- "${INSTALL_ROOT}"
  restore_evdi_config
  systemctl daemon-reload >/dev/null 2>&1 || true
}

rollback_on_error() {
  local exit_code=$?
  trap - ERR INT TERM
  set +e
  warn "Installation failed; restoring the pre-install driver and protected-file state."
  remove_partial_driver
  restore_protected
  cleanup_workdir

  if [[ -d "${STATE_DIR}" ]]; then
    local failed_backup="/var/backups/${PACKAGE_NAME}-failed-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$(dirname -- "$failed_backup")"
    mv -- "${STATE_DIR}" "$failed_backup" 2>/dev/null || true
    warn "Failure-state diagnostics were preserved at ${failed_backup}."
  fi
  warn "Rollback finished. Review ${LOG_FILE:-the terminal output}."
  exit "$exit_code"
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check-only) CHECK_ONLY=1 ;;
      --reinstall) REINSTALL=1 ;;
      --force-unsupported-kernel) FORCE_KERNEL=1 ;;
      --no-start) NO_START=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done
}

require_root() {
  [[ ${EUID} -eq 0 ]] || die "Run this installer with sudo."
}

check_platform() {
  local arch model os_id os_like version_id codename kernel_base

  arch="$(uname -m)"
  [[ "$arch" == "aarch64" ]] \
    || die "This package requires a 64-bit ARM userland/kernel (aarch64). Detected: ${arch}"

  [[ -r /proc/device-tree/model ]] || die "Unable to identify the Raspberry Pi model."
  model="$(read_pi_model)"
  [[ "$model" =~ Raspberry[[:space:]]Pi[[:space:]](4|5) ]] \
    || die "Supported hardware is Raspberry Pi 4 or Raspberry Pi 5. Detected: ${model}"

  [[ -r /etc/os-release ]] || die "Missing /etc/os-release."
  # shellcheck disable=SC1091
  source /etc/os-release
  os_id="${ID:-unknown}"
  os_like="${ID_LIKE:-}"
  version_id="${VERSION_ID:-unknown}"
  codename="${VERSION_CODENAME:-unknown}"

  if [[ "$os_id" != "raspbian" && "$os_id" != "debian" && "$os_like" != *debian* ]]; then
    die "This package is limited to Raspberry Pi OS/Raspbian and its Debian base. Detected ID=${os_id}."
  fi

  command -v systemctl >/dev/null 2>&1 || die "systemd is required."
  systemctl get-default >/dev/null 2>&1 || die "systemd is not operational."

  kernel_base="$(uname -r | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || true)"
  [[ -n "$kernel_base" ]] || die "Unable to parse kernel version: $(uname -r)"
  if (( FORCE_KERNEL == 0 )); then
    version_lt "$kernel_base" "4.15.0" \
      && die "Kernel ${kernel_base} is older than the supported minimum."
    version_gt "$kernel_base" "6.15.99" \
      && die "Kernel ${kernel_base} is outside the conservative range. Use --force-unsupported-kernel only for testing."
  fi

  log "Platform: ${model}; architecture ${arch}; OS ${os_id} ${version_id} (${codename}); kernel $(uname -r)."
  if command -v lsusb >/dev/null 2>&1 && lsusb -d "${AOC_USB_ID}" >/dev/null 2>&1; then
    log "Detected AOC I1659FWUX USB device ${AOC_USB_ID}."
  else
    warn "The monitor USB ID ${AOC_USB_ID} is not connected. Installation may continue."
  fi
}

collect_conflicts() {
  local -n result_ref=$1
  result_ref=()

  [[ -d "${STATE_DIR}" ]] && result_ref+=("this package's state directory")
  [[ -d "${INSTALL_ROOT}" ]] && result_ref+=("${INSTALL_ROOT}")
  [[ -e "${SAFE_UNIT_PATH}" ]] && result_ref+=("${SAFE_UNIT_PATH}")
  [[ -e "${UDEV_RULE_PATH}" ]] && result_ref+=("${UDEV_RULE_PATH}")
  [[ -e "${MODULE_LOAD_PATH}" ]] && result_ref+=("${MODULE_LOAD_PATH}")
  [[ -L /usr/bin/displaylink-installer || -e /usr/bin/displaylink-installer ]] \
    && result_ref+=("/usr/bin/displaylink-installer")

  local known_path
  for known_path in \
    /usr/lib/displaylink \
    /usr/lib64/displaylink \
    /etc/udev/rules.d/99-displaylink.rules \
    /usr/lib/udev/rules.d/99-displaylink.rules \
    /lib/udev/rules.d/99-displaylink.rules \
    /etc/modules-load.d/evdi.conf; do
    [[ -e "$known_path" || -L "$known_path" ]] \
      && result_ref+=("existing DisplayLink/EVDI path: ${known_path}")
  done

  if command -v dkms >/dev/null 2>&1 && dkms status 2>/dev/null | grep -qE '^evdi/'; then
    result_ref+=("existing EVDI DKMS registration")
  fi
  if command -v lsmod >/dev/null 2>&1 && lsmod 2>/dev/null | awk '{print $1}' | grep -qx evdi; then
    result_ref+=("loaded EVDI kernel module")
  fi
  if compgen -G '/usr/src/evdi-*' >/dev/null; then
    result_ref+=("existing /usr/src/evdi-* source")
  fi
  if dpkg-query -W -f='${Status}\n' displaylink-driver 2>/dev/null | grep -q 'install ok installed'; then
    result_ref+=("displaylink-driver Debian package")
  fi
  if dpkg-query -W -f='${Status}\n' evdi-dkms 2>/dev/null | grep -q 'install ok installed'; then
    result_ref+=("evdi-dkms Debian package")
  fi

  local service_file
  while IFS= read -r service_file; do
    [[ "$service_file" == "${SAFE_UNIT_PATH}" ]] && continue
    result_ref+=("DisplayLink service: ${service_file}")
  done < <(
    grep -rl --include='*.service' 'DisplayLinkManager' \
      /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system \
      2>/dev/null | sort -u
  )
}

check_existing_install() {
  if [[ -d "${STATE_DIR}" && ${REINSTALL} -eq 1 ]]; then
    log "Removing this package's existing installation before reinstall."
    "${BUNDLE_DIR}/uninstall.sh" --keep-backup
  fi

  local conflicts=()
  collect_conflicts conflicts
  if ((${#conflicts[@]})); then
    printf 'Conflicting DisplayLink/EVDI state detected:\n' >&2
    printf '  - %s\n' "${conflicts[@]}" >&2
    die "Remove the conflicting installation before using this isolated package."
  fi
}

accept_eula() {
  local answer tty_input="/dev/tty"
  printf '\nThe proprietary DisplayLink user-space files are governed by the Synaptics EULA:\n%s\n\n' \
    "${DISPLAYLINK_EULA_URL}"
  [[ -r "$tty_input" ]] \
    || die "An interactive terminal is required to review and accept the Synaptics EULA."
  read -r -p "Type AGREE to confirm that you reviewed and accept the EULA: " answer < "$tty_input"
  [[ "$answer" == "AGREE" ]] || die "EULA not accepted; no system changes were made."
}

record_dependency_state() {
  local output_file=$1
  shift
  : > "$output_file"
  local package
  for package in "$@"; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
      printf '%s\tpresent\n' "$package" >> "$output_file"
    else
      printf '%s\tabsent\n' "$package" >> "$output_file"
    fi
  done
}

install_dependencies() {
  local dependencies=(
    ca-certificates curl unzip dkms build-essential binutils pkg-config
    libdrm-dev libelf-dev libusb-1.0-0 libstdc++6 usbutils
  )
  record_dependency_state "${STATE_DIR}/dependencies-before.tsv" "${dependencies[@]}"

  log "Installing only the build/runtime packages required for DisplayLink and EVDI."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends "${dependencies[@]}"

  local kernel header_package=""
  kernel="$(uname -r)"
  if [[ ! -e "/lib/modules/${kernel}/build/Makefile" ]]; then
    log "Installing Raspberry Pi kernel headers for ${kernel}."
    if apt-cache show "linux-headers-${kernel}" >/dev/null 2>&1; then
      header_package="linux-headers-${kernel}"
    elif apt-cache show linux-headers-rpi-v8 >/dev/null 2>&1; then
      header_package="linux-headers-rpi-v8"
    elif apt-cache show raspberrypi-kernel-headers >/dev/null 2>&1; then
      header_package="raspberrypi-kernel-headers"
    else
      die "No compatible Raspberry Pi kernel-header package was found."
    fi

    record_dependency_state "${STATE_DIR}/header-before.tsv" "$header_package"
    printf '%s\n' "$header_package" > "${STATE_DIR}/header-package"
    apt-get install -y --no-install-recommends "$header_package"
  fi

  [[ -e "/lib/modules/${kernel}/build/Makefile" ]] \
    || die "Headers do not match running kernel ${kernel}. Update normally, reboot into the matching kernel, and rerun."
}

download_and_extract() {
  WORK_DIR="$(mktemp -d -t aoc-displaylink.XXXXXXXX)"
  local zip_file="${WORK_DIR}/displaylink.zip"
  local run_file

  if [[ -f "${LOCAL_VENDOR_ZIP}" ]]; then
    log "Using the local unmodified Synaptics 6.3 archive in vendor/."
    cp -- "${LOCAL_VENDOR_ZIP}" "$zip_file"
  else
    log "Downloading the unmodified DisplayLink 6.3 Ubuntu archive from Synaptics."
    curl --fail --location --retry 3 --connect-timeout 20 \
      --output "$zip_file" "${DISPLAYLINK_ZIP_URL}"
  fi

  unzip -tq "$zip_file" >/dev/null \
    || die "The DisplayLink ZIP archive failed integrity validation."

  local actual_sha256
  actual_sha256="$(sha256sum "$zip_file" | awk '{print $1}')"
  {
    printf 'expected  %s\n' "$DISPLAYLINK_ZIP_SHA256"
    printf 'actual    %s\n' "$actual_sha256"
  } > "${STATE_DIR}/downloaded-archive.sha256"
  [[ "$actual_sha256" == "$DISPLAYLINK_ZIP_SHA256" ]] \
    || die "The Synaptics archive checksum does not match the pinned DisplayLink 6.3.0-48 archive."

  mkdir -p "${WORK_DIR}/zip"
  unzip -q "$zip_file" -d "${WORK_DIR}/zip"
  run_file="$(find "${WORK_DIR}/zip" -type f -name 'displaylink-driver-*.run' -print -quit)"
  [[ -n "$run_file" ]] || die "No DisplayLink .run archive was found."
  chmod 0755 "$run_file"

  mkdir -p "${WORK_DIR}/payload"
  (
    cd "${WORK_DIR}/payload"
    "$run_file" --keep --noexec
  )

  find "${WORK_DIR}/payload" -type f -name DisplayLinkManager -print -quit | grep -q . \
    || die "The extracted archive does not contain DisplayLinkManager."
  find "${WORK_DIR}/payload" -type f \( -iname 'evdi*.tar.gz' -o -iname 'evdi*.tgz' \) -print -quit | grep -q . \
    || die "The extracted archive does not contain EVDI source."
}

extract_evdi_version() {
  local dkms_conf=$1 version
  version="$(awk -F= '
    /^[[:space:]]*PACKAGE_VERSION[[:space:]]*=/ {
      v=$2
      gsub(/^[[:space:]"'\'' ]+|[[:space:]"'\'' ]+$/, "", v)
      print v
      exit
    }
  ' "$dkms_conf")"
  if [[ -z "$version" ]]; then
    version="$(basename "$(dirname "$dkms_conf")" | sed -nE 's/^evdi-([0-9][0-9A-Za-z.+~-]*)$/\1/p')"
  fi
  printf '%s' "$version"
}

install_evdi() {
  local source_archive source_extract dkms_conf source_root destination kernel
  local library_makefile jobs
  source_archive="$(find "${WORK_DIR}/payload" -type f \
    \( -iname 'evdi*.tar.gz' -o -iname 'evdi*.tgz' \) -print -quit)"
  source_extract="${WORK_DIR}/evdi-source"
  mkdir -p "$source_extract"
  tar -xf "$source_archive" -C "$source_extract"

  dkms_conf="$(find "$source_extract" -type f -name dkms.conf -print -quit)"
  [[ -n "$dkms_conf" ]] || die "EVDI source does not contain dkms.conf."
  source_root="$(dirname -- "$dkms_conf")"
  EVDI_VERSION="$(extract_evdi_version "$dkms_conf")"
  [[ "$EVDI_VERSION" =~ ^[0-9][0-9A-Za-z.+~-]*$ ]] \
    || die "Unable to determine a safe EVDI version from the official archive."

  destination="/usr/src/evdi-${EVDI_VERSION}"
  [[ ! -e "$destination" ]] || die "EVDI source destination already exists: ${destination}"
  mkdir -p "$destination"
  cp -a -- "${source_root}/." "$destination/"
  printf '%s\n' "$EVDI_VERSION" > "${STATE_DIR}/evdi-version"

  kernel="$(uname -r)"
  log "Registering and building EVDI ${EVDI_VERSION} for kernel ${kernel}."
  dkms add -m evdi -v "$EVDI_VERSION"
  dkms build -m evdi -v "$EVDI_VERSION" -k "$kernel"
  dkms install -m evdi -v "$EVDI_VERSION" -k "$kernel"
  depmod -a "$kernel"
  modinfo -k "$kernel" evdi >/dev/null \
    || die "EVDI was built but is not discoverable by modprobe."

  library_makefile="$(find "$source_extract" -type f -path '*/library/Makefile' -print -quit)"
  [[ -n "$library_makefile" ]] \
    || die "EVDI source does not contain the libevdi library Makefile."
  EVDI_LIBRARY_DIR="$(dirname -- "$library_makefile")"
  jobs="$(nproc 2>/dev/null || printf '1')"

  log "Building libevdi ${EVDI_VERSION} from the bundled EVDI source."
  make -C "$EVDI_LIBRARY_DIR" -j"$jobs"
  compgen -G "${EVDI_LIBRARY_DIR}/libevdi.so*" >/dev/null \
    || die "The EVDI library build did not produce libevdi.so."
}

is_aarch64_elf() {
  readelf -h "$1" 2>/dev/null | grep -qE 'Machine:[[:space:]]+AArch64'
}

install_userspace_driver() {
  local manager="" candidate arch_dir firmware license_file
  while IFS= read -r -d '' candidate; do
    if is_aarch64_elf "$candidate"; then
      manager="$candidate"
      break
    fi
  done < <(find "${WORK_DIR}/payload" -type f -name DisplayLinkManager -print0)

  [[ -n "$manager" ]] \
    || die "The official archive does not contain an AArch64 DisplayLinkManager binary."
  arch_dir="$(dirname -- "$manager")"

  install -d -m 0755 "$INSTALL_ROOT"
  cp -a -- "${arch_dir}/." "${INSTALL_ROOT}/"

  [[ -d "$EVDI_LIBRARY_DIR" ]] \
    || die "The built libevdi library directory is unavailable."
  while IFS= read -r -d '' candidate; do
    cp -a -- "$candidate" "${INSTALL_ROOT}/$(basename -- "$candidate")"
  done < <(find "$EVDI_LIBRARY_DIR" -maxdepth 1 \
    \( -type f -o -type l \) -name 'libevdi.so*' -print0)

  while IFS= read -r -d '' firmware; do
    cp -a -- "$firmware" "${INSTALL_ROOT}/$(basename -- "$firmware")"
  done < <(find "${WORK_DIR}/payload" -type f -name '*.spkg' -print0)

  license_file="$(find "${WORK_DIR}/payload" -type f \
    \( -iname 'LICENSE' -o -iname 'LICENSE.txt' \) -print -quit)"
  if [[ -n "$license_file" ]]; then
    cp -a -- "$license_file" "${INSTALL_ROOT}/LICENSE"
  fi

  chown -R root:root "$INSTALL_ROOT"
  chmod 0755 "${INSTALL_ROOT}/DisplayLinkManager"
  find "$INSTALL_ROOT" -maxdepth 1 -type f -name '*.so*' -exec chmod 0755 {} + 2>/dev/null || true
  find "$INSTALL_ROOT" -maxdepth 1 -type f -name '*.spkg' -exec chmod 0644 {} + 2>/dev/null || true

  [[ -x "${INSTALL_ROOT}/DisplayLinkManager" ]] \
    || die "DisplayLinkManager was not installed correctly."
  compgen -G "${INSTALL_ROOT}/libevdi.so*" >/dev/null \
    || die "The built libevdi library was not installed beside DisplayLinkManager."

  if readelf -l "${INSTALL_ROOT}/DisplayLinkManager" 2>/dev/null | grep -q INTERP; then
    if ! LD_LIBRARY_PATH="$INSTALL_ROOT" ldd "${INSTALL_ROOT}/DisplayLinkManager" \
        > "${STATE_DIR}/displaylink-manager.ldd" 2>&1; then
      cat "${STATE_DIR}/displaylink-manager.ldd" >&2 || true
      die "DisplayLinkManager's runtime-library check failed."
    fi
    if grep -q 'not found' "${STATE_DIR}/displaylink-manager.ldd"; then
      cat "${STATE_DIR}/displaylink-manager.ldd" >&2
      die "DisplayLinkManager has an unresolved runtime-library dependency."
    fi
  fi

  log "Installed only the AArch64 DisplayLink user-space files required by this monitor."
}

configure_evdi_module() {
  cat > "${EVDI_MODPROBE_PATH}" <<'MODPROBE'
# AOC I1659FWUX: create one EVDI DRM device before the compositor starts.
options evdi initial_device_count=1
# Keep the Raspberry Pi VC4 DRM device ahead of the virtual EVDI device.
softdep evdi pre: drm_kms_helper vc4
MODPROBE

  cat > "${MODULE_LOAD_PATH}" <<'MODULES'
# Load EVDI during normal module loading, before the graphical session starts.
evdi
MODULES

  depmod -a
}

install_exact_udev_rule() {
  cat > "${UDEV_RULE_PATH}" <<UDEV
# AOC I1659FWUX only (${AOC_USB_ID}). Grant the active local session access;
# service startup remains tied to graphical.target, not USB hotplug.
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${AOC_USB_VENDOR}", ATTR{idProduct}=="${AOC_USB_PRODUCT}", MODE="0660", GROUP="video", TAG+="uaccess"
UDEV
  chmod 0644 "${UDEV_RULE_PATH}"
  udevadm control --reload-rules
}

install_safe_service() {
  cat > "${SAFE_UNIT_PATH}" <<UNIT
[Unit]
Description=AOC I1659FWUX DisplayLink Manager
Documentation=${DISPLAYLINK_EULA_URL}
After=systemd-modules-load.service display-manager.service
Wants=systemd-modules-load.service
ConditionPathExists=${INSTALL_ROOT}/DisplayLinkManager

[Service]
Type=simple
Environment=LD_LIBRARY_PATH=${INSTALL_ROOT}
ExecStartPre=/sbin/modprobe evdi
ExecStart=${INSTALL_ROOT}/DisplayLinkManager
WorkingDirectory=${INSTALL_ROOT}
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
UNIT
  chmod 0644 "${SAFE_UNIT_PATH}"
  systemctl daemon-reload
  systemctl enable "${SAFE_UNIT}" >/dev/null
  log "Installed an isolated service with no getty/login-manager conflict."
}

start_and_verify() {
  if (( NO_START == 0 )); then
    modprobe evdi || die "The EVDI module could not be loaded."
    systemctl restart "${SAFE_UNIT}"
  fi

  if systemctl is-active --quiet "${SAFE_UNIT}"; then
    log "DisplayLinkManager is running."
  elif (( NO_START == 0 )); then
    systemctl status "${SAFE_UNIT}" --no-pager || true
    die "The isolated DisplayLink service did not remain active."
  fi

  if command -v lsusb >/dev/null 2>&1 && lsusb -d "${AOC_USB_ID}" >/dev/null 2>&1; then
    sleep 3
    local connector connector_base card_name card_path found=0
    while IFS= read -r connector; do
      [[ -f "${connector}/status" ]] || continue
      [[ "$(cat "${connector}/status")" == "connected" ]] || continue
      connector_base="$(basename -- "$connector")"
      card_name="${connector_base%%-*}"
      card_path="/sys/class/drm/${card_name}"
      if readlink -f "${card_path}/device/driver" 2>/dev/null | grep -q '/evdi$'; then
        found=1
        if [[ -f "${connector}/modes" ]] && grep -qx '1920x1080' "${connector}/modes"; then
          log "The AOC native 1920x1080 mode is exposed by EVDI."
        else
          warn "An EVDI connector exists, but 1920x1080 is not yet reported."
        fi
      fi
    done < <(find /sys/class/drm -maxdepth 1 -type l -name 'card*-*' -print 2>/dev/null)
    if (( found == 0 )); then
      warn "The USB monitor is connected, but the current compositor has not exposed an active EVDI connector yet."
      warn "No session setting was changed. A normal reboot may be needed so EVDI exists before the compositor starts."
    fi
  fi
}

write_install_metadata() {
  cat > "${STATE_DIR}/install-info" <<INFO
package=${PACKAGE_NAME}
package_version=${PACKAGE_VERSION}
displaylink_release=${DISPLAYLINK_RELEASE}
displaylink_archive_sha256=${DISPLAYLINK_ZIP_SHA256}
evdi_version=${EVDI_VERSION}
usb_id=${AOC_USB_ID}
installed_at=$(date --iso-8601=seconds)
kernel=$(uname -r)
architecture=$(uname -m)
model=$(read_pi_model)
method=manual-minimal-extraction-no-vendor-installer
INFO
  cp -a -- "${BUNDLE_DIR}/uninstall.sh" "${STATE_DIR}/uninstall.sh"
  cp -a -- "${BUNDLE_DIR}/status.sh" "${STATE_DIR}/status.sh"
}

run_check_only() {
  local conflicts=()
  collect_conflicts conflicts
  if ((${#conflicts[@]})); then
    printf 'Existing DisplayLink/EVDI state that would block installation:\n' >&2
    printf '  - %s\n' "${conflicts[@]}" >&2
    return 1
  fi

  local kernel
  kernel="$(uname -r)"
  if [[ -e "/lib/modules/${kernel}/build/Makefile" ]]; then
    log "Matching kernel build headers are already available."
  else
    warn "Matching kernel headers are not currently installed; the installer will try the Raspberry Pi header packages."
  fi
  log "Compatibility checks passed. No changes were made."
}

main() {
  parse_args "$@"
  require_root
  check_platform

  if (( CHECK_ONLY == 1 )); then
    run_check_only
    exit 0
  fi

  accept_eula
  check_existing_install

  install -d -m 0750 "${LOG_DIR}"
  install -d -m 0700 "${STATE_DIR}"
  LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
  touch "$LOG_FILE"
  chmod 0640 "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1

  trap rollback_on_error ERR INT TERM
  trap cleanup_workdir EXIT

  log "Beginning ${PACKAGE_NAME} ${PACKAGE_VERSION} installation."
  snapshot_protected
  snapshot_evdi_config
  install_dependencies
  download_and_extract
  install_evdi
  install_userspace_driver
  configure_evdi_module
  install_exact_udev_rule
  install_safe_service
  verify_and_restore_protected
  write_install_metadata
  start_and_verify

  trap - ERR INT TERM
  cleanup_workdir
  WORK_DIR=""

  log "Installation completed without running Synaptics' generic system installer."
  log "No login manager, autologin, password, PAM, SSH, boot target, Wayland/X11 selection, X11 configuration, or boot configuration was changed."
  log "The installer did not reboot the Raspberry Pi."
  log "Status: sudo ${STATE_DIR}/status.sh"
  log "Uninstall: sudo ${STATE_DIR}/uninstall.sh"
}

main "$@"
