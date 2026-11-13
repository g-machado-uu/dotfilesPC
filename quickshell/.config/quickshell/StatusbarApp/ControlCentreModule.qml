import Quickshell
import QtQuick
import qs.CustomTheme
import qs.NotificationApp

// Control centre icon. The panel it opens stopped being only a notification
// list a while ago — it carries the Wi-Fi, Bluetooth, Do Not Disturb, caffeine
// and night light toggles, the output and input levels and the weather, with
// the notifications last — so the icon is a set of sliders rather than a bell,
// and the module is named for what the panel actually is.
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
//
// This is also the whole of the shell's notification alert. Nothing pops up on
// screen: a notification arriving swells that dot a few times and then leaves
// it sitting there. The daemon behind it is NotificationApp/NotificationService.
BarButton {
    id: cc

    readonly property bool hasNotifications: NotificationService.count > 0
    readonly property bool dndOn: NotificationService.dnd

    iconSrc: "../shared/icons/control-centre.svg"

    // Driven by the pulse below; 1 is the dot at rest.
    property real markScale: 1

    // The service raises this when something arrives that is worth a look (it
    // withholds it under Do Not Disturb, urgent notifications excepted).
    Connections {
        target: NotificationService
        function onArrived(notification): void { pulse.restart() }
    }

    // Three slow swells of the dot. Deliberately small and slow: it is meant
    // to be caught out of the corner of the eye, not to be answered.
    SequentialAnimation {
        id: pulse
        loops: 3

        NumberAnimation {
            target: cc
            property: "markScale"
            to: 2.6
            duration: 360
            easing.type: Easing.OutQuint
        }
        NumberAnimation {
            target: cc
            property: "markScale"
            to: 1
            duration: 420
            easing.type: Easing.OutQuint
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
        // Swells from its own centre, so the dot grows symmetrically under the
        // glyph instead of creeping sideways.
        scale: cc.markScale
        transformOrigin: Item.Center
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
