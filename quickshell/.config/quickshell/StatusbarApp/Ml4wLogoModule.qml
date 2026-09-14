import Quickshell
import QtQuick

// ML4W logo -> toggles the control centre (which took over the sidebar) via IPC.
BarButton {
    iconSrc: Quickshell.env("HOME") + "/.config/ml4w/assets/ml4w.svg"
    colorize: false
    onClicked: {
        Quickshell.execDetached(["qs", "ipc", "call", "controlcentre", "toggle"])
    }
}
