import QtQuick
import qs.CustomTheme

// The control centre's one text button: an outlined pill that fills with the
// accent on hover. Used wherever an action opens or runs something, so every
// such action in the panel looks the same.
Rectangle {
    id: pill
    property string text: ""
    signal activated()

    implicitWidth: label.implicitWidth + 22
    implicitHeight: 26
    radius: 13
    opacity: pill.enabled ? 1 : 0.4
    color: pillMouse.containsMouse ? Theme.primary : "transparent"
    border.color: Theme.primary
    border.width: 1
    Behavior on color {
        ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: pill.text
        color: pillMouse.containsMouse ? Theme.background : Theme.primary
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }

    MouseArea {
        id: pillMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.activated()
    }
}
