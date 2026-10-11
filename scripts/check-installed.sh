#!/bin/bash
# Claude Code Stop hook: refuses to let a session finish while the Aikon in
# /Applications is missing app changes that are already on main.
#
# Why: a logo fix sat committed on main for three weeks while the app in use
# was an older build, so the bug "came back" twice. Committing is not the same
# as the user having the fix.
#
# Wire it up as a Stop hook; it reads the hook JSON on stdin and prints a
# block decision only when a reinstall is needed. Machines without
# /Applications/Aikon.app are left alone.
set -u

APP="/Applications/Aikon.app"
[ -d "$APP" ] || exit 0

# Second pass after a block: let the session stop instead of looping forever
# if the reinstall itself failed — the session has already been told why.
if cat | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    exit 0
fi

cd "$(dirname "$0")/.." || exit 0

needed="$(git log -1 --format=%H main -- Sources Resources Package.swift scripts/bundle.sh 2>/dev/null || true)"
[ -n "$needed" ] || exit 0

installed="$(/usr/libexec/PlistBuddy -c 'Print :AikonCommit' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ -n "$installed" ] && git merge-base --is-ancestor "$needed" "$installed" 2>/dev/null; then
    exit 0
fi

reason="The Aikon in /Applications was built from ${installed:-an unknown commit} and does not include main's latest app change (${needed:0:7}). Run 'bash scripts/install.sh' from a checkout that contains main, then check the app runs from /Applications."
printf '{"decision":"block","reason":"%s"}\n' "$reason"
