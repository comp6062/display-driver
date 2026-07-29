#!/usr/bin/env bash
set -u
IFS=$'\n\t'
umask 022

INSTALL_ROOT="/opt/displaylink"
MANAGER="${INSTALL_ROOT}/DisplayLinkManager"
AOC_USB_ID="17e9:ff10"
RUNTIME_DIR="/run/aoc-i1659fwux-displaylink"
STATE_FILE="${RUNTIME_DIR}/broker.state"
BLOCK_FILE="${RUNTIME_DIR}/blocked-this-boot"
STABLE_SECONDS=45
POLL_SECONDS=2
EARLY_FAILURE_SECONDS=30
MANAGER_PID=""
ACTIVE_SESSION_ID=""
ACTIVE_UID=""
ACTIVE_USER=""
ACTIVE_TYPE=""
START_EPOCH=0
STOP_REQUESTED=0

log() {
  printf '[AOC SESSION BROKER %(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"
}

write_state() {
  local state=$1 detail=${2:-}
  install -d -m 0755 "$RUNTIME_DIR"
  {
    printf 'state=%s\n' "$state"
    printf 'detail=%s\n' "$detail"
    printf 'session_id=%s\n' "$ACTIVE_SESSION_ID"
    printf 'uid=%s\n' "$ACTIVE_UID"
    printf 'user=%s\n' "$ACTIVE_USER"
    printf 'session_type=%s\n' "$ACTIVE_TYPE"
    printf 'manager_pid=%s\n' "$MANAGER_PID"
    printf 'updated=%s\n' "$(date --iso-8601=seconds)"
  } > "${STATE_FILE}.tmp"
  chmod 0644 "${STATE_FILE}.tmp"
  mv -f "${STATE_FILE}.tmp" "$STATE_FILE"
}

session_value() {
  loginctl show-session "$1" --property="$2" --value 2>/dev/null || true
}

monitor_connected() {
  command -v lsusb >/dev/null 2>&1 && lsusb -d "$AOC_USB_ID" >/dev/null 2>&1
}

compositor_running_for_uid() {
  local uid=$1 process
  for process in labwc wayfire weston sway gnome-shell kwin_wayland Xorg Xwayland; do
    if pgrep -u "$uid" -x "$process" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

find_active_local_graphical_session() {
  command -v loginctl >/dev/null 2>&1 || return 1

  local sid uid user active remote class type state
  while IFS= read -r sid; do
    [[ -n "$sid" ]] || continue
    active="$(session_value "$sid" Active)"
    remote="$(session_value "$sid" Remote)"
    class="$(session_value "$sid" Class)"
    type="$(session_value "$sid" Type)"
    state="$(session_value "$sid" State)"
    uid="$(session_value "$sid" User)"
    user="$(session_value "$sid" Name)"

    [[ "$active" == "yes" ]] || continue
    [[ "$remote" == "no" ]] || continue
    [[ "$state" == "active" ]] || continue
    [[ "$class" == "user" || "$class" == "user-early" ]] || continue
    [[ "$type" == "wayland" || "$type" == "x11" ]] || continue
    [[ "$uid" =~ ^[0-9]+$ ]] || continue
    compositor_running_for_uid "$uid" || continue

    printf '%s|%s|%s|%s\n' "$sid" "$uid" "$user" "$type"
    return 0
  done < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}')

  return 1
}

same_session_is_active() {
  local result
  result="$(find_active_local_graphical_session 2>/dev/null || true)"
  [[ -n "$result" ]] || return 1
  [[ "${result%%|*}" == "$ACTIVE_SESSION_ID" ]]
}

stop_driver() {
  if [[ -n "$MANAGER_PID" ]] && kill -0 "$MANAGER_PID" 2>/dev/null; then
    kill -TERM "$MANAGER_PID" 2>/dev/null || true
    local count=0
    while kill -0 "$MANAGER_PID" 2>/dev/null && (( count < 25 )); do
      sleep 0.2
      ((count++))
    done
    kill -KILL "$MANAGER_PID" 2>/dev/null || true
    wait "$MANAGER_PID" 2>/dev/null || true
  fi
  MANAGER_PID=""

  local attempt
  for attempt in 1 2 3 4 5; do
    /sbin/modprobe -r evdi >/dev/null 2>&1 && break
    sleep 0.5
  done
}

request_stop() {
  STOP_REQUESTED=1
  write_state "stopping" "service stop requested"
  stop_driver
}

trap request_stop INT TERM HUP
trap stop_driver EXIT

[[ ${EUID} -eq 0 ]] || {
  log "ERROR: This broker must run as root."
  exit 1
}
[[ -x "$MANAGER" ]] || {
  log "ERROR: DisplayLinkManager is missing or not executable."
  exit 1
}

install -d -m 0755 "$RUNTIME_DIR"
rm -f -- "$BLOCK_FILE"
write_state "waiting" "waiting for a stable authenticated local graphical session"
log "Waiting for a stable authenticated local X11/Wayland session. EVDI remains inactive at LightDM."

while (( STOP_REQUESTED == 0 )); do
  if [[ -e "$BLOCK_FILE" ]]; then
    write_state "blocked" "driver start caused an early graphical-session loss; blocked until reboot"
    sleep "$POLL_SECONDS"
    continue
  fi

  session_record="$(find_active_local_graphical_session 2>/dev/null || true)"
  if [[ -z "$session_record" ]]; then
    ACTIVE_SESSION_ID=""
    ACTIVE_UID=""
    ACTIVE_USER=""
    ACTIVE_TYPE=""
    write_state "waiting" "no authenticated local graphical session is active"
    sleep "$POLL_SECONDS"
    continue
  fi

  IFS='|' read -r candidate_sid candidate_uid candidate_user candidate_type <<< "$session_record"
  ACTIVE_SESSION_ID="$candidate_sid"
  ACTIVE_UID="$candidate_uid"
  ACTIVE_USER="$candidate_user"
  ACTIVE_TYPE="$candidate_type"

  if ! monitor_connected; then
    write_state "waiting" "desktop is active but AOC USB monitor ${AOC_USB_ID} is not connected"
    sleep "$POLL_SECONDS"
    continue
  fi

  write_state "stabilising" "authenticated desktop detected; waiting ${STABLE_SECONDS} seconds before driver start"
  log "Detected session ${ACTIVE_SESSION_ID} (${ACTIVE_USER}, ${ACTIVE_TYPE}); requiring ${STABLE_SECONDS} seconds of continuous stability."

  stable_elapsed=0
  stable_ok=1
  while (( stable_elapsed < STABLE_SECONDS )); do
    (( STOP_REQUESTED == 0 )) || { stable_ok=0; break; }
    same_session_is_active || { stable_ok=0; break; }
    monitor_connected || { stable_ok=0; break; }
    sleep "$POLL_SECONDS"
    ((stable_elapsed += POLL_SECONDS))
  done
  (( stable_ok == 1 )) || continue

  log "Session ${ACTIVE_SESSION_ID} remained stable; loading EVDI dynamically with no pre-created devices."
  write_state "starting" "loading EVDI and starting DisplayLinkManager"
  if ! /sbin/modprobe evdi initial_device_count=0; then
    log "ERROR: EVDI could not be loaded. Retrying without changing the graphical session."
    write_state "error" "modprobe evdi failed"
    sleep 10
    continue
  fi

  LD_LIBRARY_PATH="$INSTALL_ROOT" "$MANAGER" &
  MANAGER_PID=$!
  START_EPOCH=$(date +%s)
  write_state "running" "DisplayLinkManager is active for authenticated session ${ACTIVE_SESSION_ID}"
  log "DisplayLinkManager started as PID ${MANAGER_PID}."

  unexpected_exit=0
  while (( STOP_REQUESTED == 0 )); do
    if ! kill -0 "$MANAGER_PID" 2>/dev/null; then
      unexpected_exit=1
      break
    fi
    if ! same_session_is_active; then
      elapsed=$(( $(date +%s) - START_EPOCH ))
      if (( elapsed < EARLY_FAILURE_SECONDS )); then
        printf 'session %s disappeared %s seconds after driver start\n' "$ACTIVE_SESSION_ID" "$elapsed" > "$BLOCK_FILE"
        chmod 0644 "$BLOCK_FILE"
        log "The desktop session disappeared ${elapsed} seconds after driver start; blocking further starts for this boot to prevent a login loop."
      else
        log "Graphical session ${ACTIVE_SESSION_ID} ended; stopping DisplayLink before the greeter is used."
      fi
      break
    fi
    if ! monitor_connected; then
      log "AOC monitor disconnected; stopping DisplayLink until it is reconnected during an authenticated desktop session."
      break
    fi
    sleep "$POLL_SECONDS"
  done

  stop_driver
  if (( STOP_REQUESTED == 1 )); then
    break
  fi

  if (( unexpected_exit == 1 )); then
    log "DisplayLinkManager exited unexpectedly; waiting before retrying."
    write_state "error" "DisplayLinkManager exited unexpectedly"
    sleep 10
  else
    write_state "waiting" "driver stopped; waiting for a stable authenticated desktop session"
    sleep "$POLL_SECONDS"
  fi
done

write_state "stopped" "broker exited"
exit 0
