import Quickshell
import Quickshell.Io
import QtQuick
import qs.CustomTheme

// Control centre icon. The panel it opens stopped being only a notification
// list a while ago — it carries the Wi-Fi, Bluetooth, Do Not Disturb, caffeine
// and night light toggles, the output and input levels and the weather, with
// the notification count last — so the icon is a set of sliders rather than a
// bell, and the module is named for what the panel actually is.
//
// The state the bell used to carry is not lost, it is demoted to a mark under
// the glyph: a dot while notifications are waiting, and a bar while Do Not
// Disturb is on. DND outranks the count, because the whole point of it is that
// the count should stop asking for attention.
//
// The mark sits below the glyph rather than in the corner: the corner of an
// 18px lucide icon is already ink, and a badge there reads as part of the
// drawing. Underneath it is empty, and still well inside the accent circle
// that fills in on hover.
BarButton {
    id: cc

    property bool hasNotifications: false
    property bool dndOn: false

    iconSrc: "../shared/icons/control-centre.svg"

    // swaync's waybar subscription emits a JSON line on every add and close;
    // `alt` carries the Do Not Disturb state.
    Process {
        command: ["swaync-client", "-swb"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    let obj = JSON.parse(data)
                    cc.hasNotifications = parseInt(obj.text) > 0
                    cc.dndOn = String(obj.alt || "").indexOf("dnd") >= 0
                } catch (e) {
                    // Ignore malformed lines.
                }
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 24
        // A dot for waiting notifications, a bar for Do Not Disturb.
        width: cc.dndOn ? 9 : 4
        height: 3
        radius: height / 2
        visible: cc.dndOn || cc.hasNotifications
        // Follows the icon, so it stays legible once the accent circle fills.
        color: cc.active ? Theme.background : Theme.primary
        Behavior on color {
            ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
        }
        Behavior on width {
            NumberAnimation { duration: 200; easing.type: Easing.OutQuint }
        }
    }
}
