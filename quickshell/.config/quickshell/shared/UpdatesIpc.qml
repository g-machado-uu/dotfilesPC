pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The "updates" IPC target. It lives here rather than in UpdatesModule because
// there is an updates module on every monitor's bar, and a target can only be
// registered once: `reset` and `refresh` have to reach all of them.
Singleton {
    id: bus

    signal reset()
    signal refresh()

    // Let external scripts drive the module via `qs ipc call updates ...`.
    // `reset` clears the count immediately (e.g. right after an update run,
    // so the module hides itself without waiting for the next poll); `refresh`
    // re-runs the check script on demand.
    IpcHandler {
        target: "updates"
        function reset(): void { bus.reset() }
        function refresh(): void { bus.refresh() }
    }
}
