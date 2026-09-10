import Quickshell
import Quickshell.Io
import QtQuick

// Notification centre icon. Shows a filled bell while notifications are
// waiting, and a struck-through one while Do Not Disturb is on. The panel it
// opens hangs off this button and is wired up by the status bar.
BarButton {
    id: bell

    property bool hasNotifications: false
    property bool dndOn: false

    iconSrc: dndOn
        ? "../shared/icons/bell-off.svg"
        : (hasNotifications ? "../shared/icons/bell-filled.svg"
                            : "../shared/icons/bell.svg")

    // swaync's waybar subscription emits a JSON line on every add and close;
    // `alt` carries the Do Not Disturb state.
    Process {
        command: ["swaync-client", "-swb"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    let obj = JSON.parse(data)
                    bell.hasNotifications = parseInt(obj.text) > 0
                    bell.dndOn = String(obj.alt || "").indexOf("dnd") >= 0
                } catch (e) {
                    // Ignore malformed lines.
                }
            }
        }
    }
}
