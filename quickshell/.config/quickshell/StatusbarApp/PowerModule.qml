import Quickshell
import QtQuick

// Power menu icon. The panel it opens hangs off this button and is wired up by
// the status bar (which owns the panel), so there is no action here.
BarButton {
    iconSrc: "../shared/icons/power.svg"
}
