#!/usr/bin/env bash
set -u
IFS=$'\n\t'
umask 022

INSTALL_ROOT="/opt/displaylink"
MANAGER="${INSTALL_ROOT}/DisplayLinkManager"
RUNTIME_DIR="/run/aoc-i1659fwux-displaylink"
MANAGER_PID=""
ACTIVE_REQUEST=""
ACTIVE_UID=""
START_EPOCH=0
STOP_REQUESTED=0

log() {
  printf '[AOC SESSION BROKER %(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"
}

session_property() {
  loginctl show-session "$1" --property="$2" --value 2>/dev/null || true
}

request_value() {
  local file=$1 key=$2
  sed -n "s/^${key}=//p" "$file" 2>/dev/null | head -n1
}

request_is_valid() {
  local file=$1 base uid owner session_id request_pid now mtime
  local user active remote class type state

  [[ -f "$file" && ! -L "$file" ]] || return 1
  base="$(basename -- "$file")"
  [[ "$base" =~ ^session-([0-9]+)\.request$ ]] || return 1
  uid="${BASH_REMATCH[1]}"
  (( uid >= 1000 )) || return 1

  owner="$(stat -c '%u' "$file" 2>/dev/null || true)"
  [[ "$owner" == "$uid" ]] || return 1
  mtime="$(stat -c '%Y' "$file" 2>/dev/null || printf '0')"
  now="$(date +%s)"
  (( now - mtime <= 8 )) || return 1

  [[ "$(request_value "$file" uid)" == "$uid" ]] || return 1
  session_id="$(request_value "$file" session_id)"
  request_pid="$(request_value "$file" request_pid)"
  [[ "$session_id" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  [[ "$request_pid" =~ ^[0-9]+$ ]] || return 1
  [[ -d "/proc/${request_pid}" ]] || return 1
  [[ "$(stat -c '%u' "/proc/${request_pid}" 2>/dev/null || true)" == "$uid" ]] || return 1

  user="$(session_property "$session_id" User)"
  active="$(session_property "$session_id" Active)"
  remote="$(session_property "$session_id" Remote)"
  class="$(session_property "$session_id" Class)"
  type="$(session_property "$session_id" Type)"
  state="$(session_property "$session_id" State)"

  [[ "$user" == "$uid" ]] || return 1
  [[ "$active" == "yes" && "$remote" == "no" && "$state" == "active" ]] || return 1
  [[ "$class" == "user" || "$class" == "user-early" ]] || return 1
  [[ "$type" == "x11" || "$type" == "wayland" ]] || return 1
  [[ ! -e "${RUNTIME_DIR}/blocked-${uid}" ]] || return 1
  return 0
}

find_valid_request() {
  local file
  for file in "${RUNTIME_DIR}"/session-*.request; do
    [[ -e "$file" ]] || continue
    if request_is_valid "$file"; then
      printf '%s\n' "$file"
      return 0
    fi
  done
  return 1
}

stop_manager() {
  if [[ -n "$MANAGER_PID" ]] && kill -0 "$MANAGER_PID" 2>/dev/null; then
    kill -TERM "$MANAGER_PID" 2>/dev/null || true
    local count=0
    while kill -0 "$MANAGER_PID" 2>/dev/null && (( count < 30 )); do
      sleep 0.2
      ((count++))
    done
    kill -KILL "$MANAGER_PID" 2>/dev/null || true
    wait "$MANAGER_PID" 2>/dev/null || true
  fi
  MANAGER_PID=""
  ACTIVE_REQUEST=""
  ACTIVE_UID=""
  START_EPOCH=0
  /sbin/modprobe -r evdi >/dev/null 2>&1 || true
}

block_for_boot() {
  local uid=$1 reason=$2
  printf '%s\n' "$reason" > "${RUNTIME_DIR}/blocked-${uid}"
  chmod 0600 "${RUNTIME_DIR}/blocked-${uid}"
  log "Driver was blocked for the remainder of this boot to prevent a repeated login loop: ${reason}"
}

request_stop() {
  STOP_REQUESTED=1
  stop_manager
}

trap request_stop INT TERM HUP
trap stop_manager EXIT

[[ ${EUID} -eq 0 ]] || {
  log "ERROR: This broker must run as root."
  exit 1
}
[[ -x "$MANAGER" ]] || {
  log "ERROR: DisplayLinkManager is missing or not executable."
  exit 1
}
command -v loginctl >/dev/null 2>&1 || {
  log "ERROR: loginctl is required."
  exit 1
}

install -d -m 1777 "$RUNTIME_DIR"
rm -f -- "${RUNTIME_DIR}"/session-*.request "${RUNTIME_DIR}"/blocked-* 2>/dev/null || true
log "Waiting for an authenticated desktop autostart request. EVDI and DisplayLinkManager are inactive at LightDM."

while (( STOP_REQUESTED == 0 )); do
  if [[ -z "$MANAGER_PID" ]]; then
    request="$(find_valid_request || true)"
    if [[ -z "$request" ]]; then
      sleep 2
      continue
    fi

    uid="$(basename -- "$request")"
    uid="${uid#session-}"
    uid="${uid%.request}"

    # The requester has already waited for desktop startup. Require another
    # continuous ten seconds of valid heartbeats before touching DRM.
    stable=1
    for _ in $(seq 1 5); do
      sleep 2
      if ! request_is_valid "$request"; then
        stable=0
        break
      fi
    done
    (( stable == 1 )) || continue

    log "Authenticated desktop request is stable for UID ${uid}; loading EVDI with zero pre-created devices."
    if ! /sbin/modprobe evdi initial_device_count=0; then
      log "ERROR: EVDI could not be loaded."
      block_for_boot "$uid" "EVDI module load failed"
      sleep 2
      continue
    fi

    LD_LIBRARY_PATH="$INSTALL_ROOT" "$MANAGER" &
    MANAGER_PID=$!
    ACTIVE_REQUEST="$request"
    ACTIVE_UID="$uid"
    START_EPOCH="$(date +%s)"
    log "DisplayLinkManager started after the desktop was fully established."
    sleep 2
    continue
  fi

  if ! kill -0 "$MANAGER_PID" 2>/dev/null; then
    elapsed=$(( $(date +%s) - START_EPOCH ))
    wait "$MANAGER_PID" 2>/dev/null || true
    if (( elapsed < 60 )) && [[ -n "$ACTIVE_UID" ]]; then
      block_for_boot "$ACTIVE_UID" "DisplayLinkManager exited ${elapsed}s after startup"
    fi
    stop_manager
    sleep 2
    continue
  fi

  if ! request_is_valid "$ACTIVE_REQUEST"; then
    elapsed=$(( $(date +%s) - START_EPOCH ))
    if (( elapsed < 60 )) && [[ -n "$ACTIVE_UID" ]]; then
      block_for_boot "$ACTIVE_UID" "graphical session disappeared ${elapsed}s after DisplayLink startup"
    else
      log "Authenticated desktop session ended; stopping DisplayLink before LightDM resumes."
    fi
    stop_manager
    sleep 2
    continue
  fi

  sleep 2
done

exit 0
