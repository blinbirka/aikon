#!/bin/bash
# Aikon session-state hook.
#
# Reads a Claude Code hook event JSON from stdin and drops a marker file in
# the state folder that Aikon's StateReader.swift watches. No network calls,
# no external services — this is what makes the menu-bar panel work without
# the author's personal notify.sh/telegram setup.
#
# Which marker to write is passed explicitly as $1 by the registration in
# settings-patch.py (one Notification matcher -> one argument, see that
# file's REGISTRATIONS and the doc link there), so this script never has to
# guess from free-form notification text:
#   permission -> needs permission
#   answer     -> needs an answer
#   done       -> turn finished
#
# Marker contract (see Sources/Aikon/StateReader.swift):
#   {session_id}.⚠️     — needs permission
#   {session_id}.❓     — needs an answer
#   {session_id}.🏁     — turn finished
#   {session_id}.quiet  — sentinel written alongside 🏁: StateReader treats it
#                          as "created when Claude finishes a turn"
# File contents: unix timestamp (seconds) as plain text. StateReader falls
# back to the file's mtime if the contents can't be parsed, so a write
# failure here degrades gracefully instead of breaking the panel.
#
# This script must NEVER break the calling Claude Code session: any failure
# exits 0 silently.

set -u

# Same default path StateReader.swift is compiled with. Override for the
# installer's dry runs / tests via AIKON_STATE_DIR.
STATE_DIR="${AIKON_STATE_DIR:-$HOME/.claude/tools/notify/state}"

# Explicit marker kind, passed by the settings.json registration. Empty if
# this script is invoked without an argument (e.g. run by hand).
ARG="${1:-}"

write_marker() {
  # $1 = file name (session_id + suffix), $2 = unix timestamp
  printf '%s' "$2" > "$STATE_DIR/$1" 2>/dev/null
}

main() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0

  local payload
  payload=$(cat) || return 0
  [ -z "$payload" ] && return 0

  # Pull event name / session id out of the hook JSON. Field names match
  # Claude Code's documented hook payload (hook_event_name, session_id).
  # Printed one per line so bash doesn't need a JSON parser of its own.
  local parsed
  parsed=$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("hook_event_name", ""))
print(d.get("session_id", ""))
' 2>/dev/null)
  [ -z "$parsed" ] && return 0

  local event session
  event=$(printf '%s\n' "$parsed" | sed -n '1p')
  session=$(printf '%s\n' "$parsed" | sed -n '2p')

  [ -z "$event" ] && return 0
  [ -z "$session" ] && return 0

  local now
  now=$(date +%s)

  # Prefer the explicit marker kind passed by settings.json. Fall back to
  # guessing from hook_event_name only when the hook is invoked without an
  # argument (e.g. a manual test run against an older registration).
  case "$ARG" in
    permission) write_marker "$session.⚠️" "$now"; return 0 ;;
    answer)     write_marker "$session.❓" "$now"; return 0 ;;
    done)       write_marker "$session.🏁" "$now"
                write_marker "$session.quiet" "$now"
                return 0 ;;
  esac

  case "$event" in
    PermissionRequest)
      write_marker "$session.⚠️" "$now"
      ;;
    Elicitation)
      write_marker "$session.❓" "$now"
      ;;
    Stop)
      write_marker "$session.🏁" "$now"
      write_marker "$session.quiet" "$now"
      ;;
    *)
      : # unrelated hook event — nothing to mark
      ;;
  esac
}

main
exit 0
