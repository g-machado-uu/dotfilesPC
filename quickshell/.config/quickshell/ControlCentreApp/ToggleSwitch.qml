import QtQuick
import qs.CustomTheme

// The control centre's on/off switch. It only reports the click; the owner
// runs the command and feeds the real state back through `on`.
Rectangle {
    id: sw
    property bool on: false
    signal toggled()

    implicitWidth: 42
    implicitHeight: 22
    radius: 11
    color: sw.on ? Theme.primary : "transparent"
    border.color: Theme.primary
    border.width: 1
    Behavior on color {
        ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
    }

    Rectangle {
        width: 16
        height: 16
        radius: 8
        y: 3
        x: sw.on ? parent.width - width - 3 : 3
        color: sw.on ? Theme.background : Theme.primary
        Behavior on x {
            NumberAnimation { duration: 180; easing.type: Easing.OutQuint }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled()
    }
}
