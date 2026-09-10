#!/usr/bin/env bash
# Toggle the floating-bubble system monitor.
#
# A lock guards against a single keypress launching two copies (a duplicate
# Hyprland binding, a double-fired dispatcher, an impatient double tap): the
# lock is held by the quickshell process itself, so it clears when it exits.
# Presses that land within the startup grace period are ignored rather than
# treated as "close", so one keypress can never open and close in one go.
set -u

CONFIG="$HOME/.config/quickshell/SysMonitor/shell.qml"
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}"
LOCK="$RUNDIR/quickshell-sysmonitor.lock"
STAMP="$RUNDIR/quickshell-sysmonitor.stamp"
GRACE_MS=1200

exec 9>"$LOCK"

if flock -n 9; then
    # nothing running: claim the lock (fd 9 survives the exec) and open
    date +%s%3N >"$STAMP"
    exec qs -p "$CONFIG"
fi

# already open: ignore a duplicate press that arrives while it is still starting
started=$(cat "$STAMP" 2>/dev/null || echo 0)
if [ $(( $(date +%s%3N) - started )) -lt "$GRACE_MS" ]; then
    exit 0
fi

# ask it to close: the bubbles drift away and the process exits by itself
qs -p "$CONFIG" ipc call sysmon close >/dev/null 2>&1
