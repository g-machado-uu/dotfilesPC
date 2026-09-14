import QtQuick
import qs.CustomTheme

// A round media transport button (previous / play-pause / next). Shared by the
// bar's media dropdown and the control centre, so the two look and behave the
// same.
Rectangle {
    id: btn
    property string iconSrc: ""
    property real diameter: 34
    signal activated()

    implicitWidth: diameter
    implicitHeight: diameter
    radius: diameter / 2
    opacity: enabled ? 1 : 0.4
    color: btnMouse.containsMouse ? Theme.primary : "transparent"
    border.color: Theme.primary
    border.width: 1
    Behavior on color {
        ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
    }

    IconGlyph {
        anchors.centerIn: parent
        source: btn.iconSrc
        size: btn.diameter * 0.45
        color: btnMouse.containsMouse ? Theme.background : Theme.primary
    }

    MouseArea {
        id: btnMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.activated()
    }
}
