#!/usr/bin/env bash
set -u
IFS=$'\n\t'
umask 077

RUNTIME_DIR="/run/aoc-i1659fwux-displaylink"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/aoc-i1659fwux-session-request.lock"
REQUEST_FILE=""
SESSION_ID="${XDG_SESSION_ID:-}"

log() {
  printf '[AOC SESSION REQUEST %(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"
}

session_property() {
  loginctl show-session "$1" --property="$2" --value 2>/dev/null || true
}

find_own_graphical_session() {
  local uid=$1 session_id user active remote class type state

  if [[ -n "$SESSION_ID" ]]; then
    user="$(session_property "$SESSION_ID" User)"
    active="$(session_property "$SESSION_ID" Active)"
    remote="$(session_property "$SESSION_ID" Remote)"
    class="$(session_property "$SESSION_ID" Class)"
    type="$(session_property "$SESSION_ID" Type)"
    state="$(session_property "$SESSION_ID" State)"
    if [[ "$user" == "$uid" && "$active" == "yes" && "$remote" == "no" \
        && "$state" == "active" && ( "$class" == "user" || "$class" == "user-early" ) \
        && ( "$type" == "x11" || "$type" == "wayland" ) ]]; then
      printf '%s\n' "$SESSION_ID"
      return 0
    fi
  fi

  while read -r session_id _; do
    [[ -n "$session_id" ]] || continue
    user="$(session_property "$session_id" User)"
    active="$(session_property "$session_id" Active)"
    remote="$(session_property "$session_id" Remote)"
    class="$(session_property "$session_id" Class)"
    type="$(session_property "$session_id" Type)"
    state="$(session_property "$session_id" State)"
    [[ "$user" == "$uid" ]] || continue
    [[ "$active" == "yes" && "$remote" == "no" && "$state" == "active" ]] || continue
    [[ "$class" == "user" || "$class" == "user-early" ]] || continue
    [[ "$type" == "x11" || "$type" == "wayland" ]] || continue
    printf '%s\n' "$session_id"
    return 0
  done < <(loginctl list-sessions --no-legend 2>/dev/null)

  return 1
}

cleanup() {
  if [[ -n "$REQUEST_FILE" && -e "$REQUEST_FILE" ]]; then
    local owner
    owner="$(stat -c '%u' "$REQUEST_FILE" 2>/dev/null || true)"
    [[ "$owner" == "$(id -u)" ]] && rm -f -- "$REQUEST_FILE"
  fi
}

command -v loginctl >/dev/null 2>&1 || exit 0
command -v flock >/dev/null 2>&1 || exit 0

uid="$(id -u)"
(( uid >= 1000 )) || exit 0
[[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR}" ]] || exit 0
[[ "${XDG_SESSION_TYPE:-}" == "x11" || "${XDG_SESSION_TYPE:-}" == "wayland" ]] || exit 0
if [[ "${XDG_SESSION_TYPE:-}" == "x11" ]]; then
  [[ -n "${DISPLAY:-}" ]] || exit 0
else
  [[ -n "${WAYLAND_DISPLAY:-}" ]] || exit 0
fi

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0
trap cleanup EXIT INT TERM HUP

# XDG autostart runs inside the authenticated desktop. Waiting here keeps the
# driver away from LightDM and gives the compositor, panel and user bus time to
# finish startup before any EVDI device is created.
sleep 25

session_id="$(find_own_graphical_session "$uid" || true)"
[[ -n "$session_id" ]] || exit 0

for _ in $(seq 1 30); do
  [[ -d "$RUNTIME_DIR" && -w "$RUNTIME_DIR" ]] && break
  sleep 1
done
[[ -d "$RUNTIME_DIR" && -w "$RUNTIME_DIR" ]] || exit 0

REQUEST_FILE="${RUNTIME_DIR}/session-${uid}.request"
log "Authenticated desktop is ready; requesting the display-only driver for session ${session_id}."

while true; do
  current_session="$(find_own_graphical_session "$uid" || true)"
  [[ "$current_session" == "$session_id" ]] || break

  temp_file="${RUNTIME_DIR}/.session-${uid}.$$.tmp"
  {
    printf 'uid=%s\n' "$uid"
    printf 'session_id=%s\n' "$session_id"
    printf 'session_type=%s\n' "${XDG_SESSION_TYPE:-unknown}"
    printf 'request_pid=%s\n' "$$"
    printf 'heartbeat=%s\n' "$(date +%s)"
  } > "$temp_file"
  chmod 0600 "$temp_file"
  mv -f -- "$temp_file" "$REQUEST_FILE"
  sleep 2
done

exit 0
