import QtQuick

// A single thermometer: stem + bulb, with the mercury animated.
Item {
    id: t

    required property var pal
    required property string label
    required property real temp
    property real minTemp: 20
    property real maxTemp: 100
    required property color col
    property real unitSize: 150     // parent bubble diameter, drives scaling

    readonly property real frac: Math.max(0, Math.min(1, (temp - minTemp) / (maxTemp - minTemp)))
    property real shownFrac: 0
    onFracChanged: shownFrac = frac
    Behavior on shownFrac { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }

    readonly property color track: Qt.rgba(pal.outline_variant.r, pal.outline_variant.g,
                                           pal.outline_variant.b, 0.85)

    implicitWidth: unitSize * 0.21
    implicitHeight: caption.height + tube.height + value.height + unitSize * 0.03

    Text {
        id: caption
        anchors.horizontalCenter: parent.horizontalCenter
        text: t.label
        color: t.col
        font.family: t.pal.fontFamily
        font.pixelSize: t.unitSize * 0.072
        font.weight: Font.DemiBold
        font.letterSpacing: t.unitSize * 0.008
    }

    Item {
        id: tube
        anchors.top: caption.bottom
        anchors.topMargin: t.unitSize * 0.022
        anchors.horizontalCenter: parent.horizontalCenter
        width: t.width
        height: t.unitSize * 0.38

        readonly property real bulbD: t.width * 0.66
        readonly property real stemW: t.width * 0.44
        readonly property real stemBottom: height - bulbD / 2
        readonly property real stemRange: stemBottom - t.unitSize * 0.012

        // stem track
        Rectangle {
            width: tube.stemW
            height: tube.stemBottom
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            color: t.track
        }

        // bulb track
        Rectangle {
            width: tube.bulbD
            height: width
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            color: t.track
        }

        // mercury: bulb
        Rectangle {
            width: tube.bulbD * 0.76
            height: width
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: tube.bulbD * 0.12
            color: t.col
        }

        // mercury: column
        Rectangle {
            width: tube.stemW * 0.62
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            height: Math.max(width, t.shownFrac * tube.stemRange)
            y: tube.stemBottom - height
            color: t.col
        }

        // graduations
        Repeater {
            model: 5
            Rectangle {
                width: t.unitSize * 0.028
                height: 1
                color: Qt.rgba(t.pal.outline.r, t.pal.outline.g, t.pal.outline.b, 0.5)
                x: tube.width / 2 + tube.stemW / 2 + t.unitSize * 0.012
                y: t.unitSize * 0.02 + index * (tube.stemRange - t.unitSize * 0.02) / 4
            }
        }
    }

    Text {
        id: value
        anchors.top: tube.bottom
        anchors.topMargin: t.unitSize * 0.012
        anchors.horizontalCenter: parent.horizontalCenter
        text: t.temp > 0 ? Math.round(t.temp) + "°" : "--"
        color: t.pal.on_surface
        font.family: t.pal.fontFamily
        font.pixelSize: t.unitSize * 0.105
        font.weight: Font.DemiBold
    }
}
