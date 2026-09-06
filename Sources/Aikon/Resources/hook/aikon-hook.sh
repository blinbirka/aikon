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

# Pulls a single string field out of a flat JSON object using only shell
# builtins + sed — no python3, no jq, nothing beyond what a stock macOS
# ships. Good enough for this payload: both fields we read
# (hook_event_name, session_id) are always plain JSON strings, never
# nested objects/arrays, and Claude Code's hook JSON is a single object.
# Tolerates spaces around the colon and the field appearing anywhere in
# the payload; does not attempt to unescape JSON string escapes, since
# neither field is expected to contain any.
json_field() {
  # $1 = field name, $2 = raw JSON text (may span multiple lines)
  printf '%s' "$2" | tr '\n' ' ' | sed -E -n \
    "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\\1/p" | head -n 1
}

main() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0

  local payload
  payload=$(cat) || return 0
  [ -z "$payload" ] && return 0

  # Field names match Claude Code's documented hook payload
  # (hook_event_name, session_id).
  local event session
  event=$(json_field "hook_event_name" "$payload")
  session=$(json_field "session_id" "$payload")

  [ -z "$event" ] && return 0
  [ -z "$session" ] && return 0

  # session_id ends up in a file path below — refuse anything that could
  # escape STATE_DIR instead of trusting it blindly.
  case "$session" in
    */*|*..*|*$'\n'*) return 0 ;;
  esac

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
