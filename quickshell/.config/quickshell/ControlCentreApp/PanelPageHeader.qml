import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.shared

// Header for a control-centre sub-page: back arrow, title, a refresh
// button and the radio's own on/off switch.
RowLayout {
    id: header

    property string title: ""
    property bool toggleOn: false
    property bool busy: false

    signal back()
    signal toggled()
    signal refresh()

    spacing: 8

    component HeaderButton: Rectangle {
        property string iconSrc: ""
        signal activated()
        implicitWidth: 28
        implicitHeight: 28
        radius: 14
        color: hover.containsMouse ? Theme.primary : "transparent"
        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutQuint }
        }
        IconGlyph {
            anchors.centerIn: parent
            source: parent.iconSrc
            size: 16
            color: hover.containsMouse ? Theme.background : Theme.primary
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
    }

    HeaderButton {
        iconSrc: "../shared/icons/back.svg"
        onActivated: header.back()
    }

    Text {
        Layout.fillWidth: true
        text: header.title
        color: Theme.primary
        font.family: Theme.fontFamily
        font.pixelSize: 15
        font.bold: true
    }

    // Spins while a connection attempt is in flight.
    IconGlyph {
        visible: header.busy
        source: "../shared/icons/refresh.svg"
        size: 15
        color: Theme.primary
        RotationAnimation on rotation {
            from: 0; to: 360
            duration: 1100
            loops: Animation.Infinite
            running: header.busy
        }
    }

    HeaderButton {
        iconSrc: "../shared/icons/refresh.svg"
        visible: !header.busy
        onActivated: header.refresh()
    }

    // The radio switch, same shape as the sidebar's switches.
    Rectangle {
        implicitWidth: 42
        implicitHeight: 22
        radius: 11
        color: header.toggleOn ? Theme.primary : "transparent"
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
            x: header.toggleOn ? parent.width - width - 3 : 3
            color: header.toggleOn ? Theme.background : Theme.primary
            Behavior on x {
                NumberAnimation { duration: 180; easing.type: Easing.OutQuint }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: header.toggled()
        }
    }
}
