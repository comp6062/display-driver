#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REPOSITORY="comp6062/display-driver"
REF="${DISPLAY_DRIVER_REF:-main}"
INSTALLER_NAME="aoc-i1659fwux-rpi4-single-file-installer.sh"
INSTALLER_SHA256="272920d4c08a1b4759c30b6efcfb1b71b59c7778e7a1f597f49bfbc4e625d11e"
RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/${REF}"
INSTALLER_URL="${RAW_BASE}/${INSTALLER_NAME}"
TEMP_DIR=""

log() {
    printf '[display-driver] %s\n' "$*"
}

die() {
    printf '[display-driver] ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}
trap cleanup EXIT

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "Run the remote installer with sudo, for example: curl -fsSL ${RAW_BASE}/install.sh | sudo bash"
fi

command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required but was not found."

TEMP_DIR="$(mktemp -d /tmp/display-driver-remote.XXXXXX)"
DOWNLOADED_INSTALLER="$TEMP_DIR/$INSTALLER_NAME"

if command -v curl >/dev/null 2>&1; then
    log "Downloading the CODELOCK installer from GitHub."
    curl --fail --silent --show-error --location \
        --proto '=https' --tlsv1.2 --retry 3 \
        --output "$DOWNLOADED_INSTALLER" "$INSTALLER_URL"
elif command -v wget >/dev/null 2>&1; then
    log "Downloading the CODELOCK installer from GitHub."
    wget --quiet --https-only --tries=3 \
        --output-document="$DOWNLOADED_INSTALLER" "$INSTALLER_URL"
else
    die "Either curl or wget is required to download the installer."
fi

actual_sha256="$(sha256sum "$DOWNLOADED_INSTALLER" | awk '{print $1}')"
if [[ "$actual_sha256" != "$INSTALLER_SHA256" ]]; then
    die "Installer checksum mismatch. Expected $INSTALLER_SHA256 but received $actual_sha256. Nothing was executed."
fi

chmod 0755 "$DOWNLOADED_INSTALLER"
log "Checksum verified: $actual_sha256"
log "Starting the AOC I1659FWUX installer."

# When this wrapper is piped into Bash, stdin contains the wrapper itself rather
# than the user's keyboard. Reconnect stdin to the controlling terminal so the
# unchanged main installer can display and receive its EULA prompt normally.
if [[ -r /dev/tty ]]; then
    "$DOWNLOADED_INSTALLER" "$@" </dev/tty
else
    "$DOWNLOADED_INSTALLER" "$@"
fi
