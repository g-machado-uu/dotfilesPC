import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.shared

// Transport controls for whatever is playing, dropping out of the bar's media
// module. Content only: the silhouette and the drop come from BarPanel.
Item {
    id: root

    readonly property real panelWidth: 360
    readonly property real panelHeight: 132

    property bool isOpen: false
    signal closeRequested()

    readonly property var player: {
        let list = Mpris.players.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].isPlaying)
                return list[i]
        }
        return list.length > 0 ? list[0] : null
    }

    readonly property string artist: {
        if (!root.player)
            return ""
        if (root.player.trackArtist)
            return root.player.trackArtist
        if (root.player.trackArtists && root.player.trackArtists.length > 0)
            return root.player.trackArtists[0]
        return root.player.identity ? root.player.identity : ""
    }

    // Position only needs to tick while the panel is actually on screen.
    Timer {
        interval: 1000
        repeat: true
        running: root.isOpen && root.player !== null && root.player.isPlaying
        onTriggered: progress.refresh()
    }

    component TransportButton: Rectangle {
        id: btn
        property string iconSrc: ""
        property real diameter: 34
        signal activated()

        implicitWidth: diameter
        implicitHeight: diameter
        radius: diameter / 2
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Album art when the player offers it, a note glyph when it does not.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 52
                implicitHeight: 52
                radius: 10
                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)
                clip: true

                Image {
                    anchors.fill: parent
                    source: (root.player && root.player.trackArtUrl)
                        ? root.player.trackArtUrl : ""
                    visible: source !== ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                IconGlyph {
                    anchors.centerIn: parent
                    visible: !root.player || !root.player.trackArtUrl
                    source: "../shared/icons/music.svg"
                    size: 22
                    color: Theme.primary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: root.player
                        ? (root.player.trackTitle ? root.player.trackTitle : "Playing")
                        : "Nothing playing"
                    elide: Text.ElideRight
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: root.artist
                    visible: text !== ""
                    elide: Text.ElideRight
                    color: Theme.on_background
                    opacity: 0.8
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }
        }

        // Progress. Players that do not report a length simply show nothing.
        Item {
            id: progress
            Layout.fillWidth: true
            implicitHeight: 4

            function refresh(): void {
                progress.fraction = (root.player && root.player.length > 0)
                    ? Math.min(1, root.player.position / root.player.length)
                    : 0
            }
            property real fraction: 0

            visible: root.player !== null && root.player.length > 0

            Rectangle {
                anchors.fill: parent
                radius: 2
                color: Theme.primary
                opacity: 0.2
            }
            Rectangle {
                width: parent.width * progress.fraction
                height: parent.height
                radius: 2
                color: Theme.primary
                Behavior on width {
                    NumberAnimation { duration: 400; easing.type: Easing.OutQuint }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 14

            Item { Layout.fillWidth: true }

            TransportButton {
                iconSrc: "../shared/icons/skip-back.svg"
                enabled: root.player !== null
                opacity: enabled ? 1 : 0.4
                onActivated: if (root.player) root.player.previous()
            }

            TransportButton {
                diameter: 42
                iconSrc: (root.player && root.player.isPlaying)
                    ? "../shared/icons/pause.svg" : "../shared/icons/play.svg"
                enabled: root.player !== null
                opacity: enabled ? 1 : 0.4
                onActivated: if (root.player) root.player.isPlaying = !root.player.isPlaying
            }

            TransportButton {
                iconSrc: "../shared/icons/skip-forward.svg"
                enabled: root.player !== null
                opacity: enabled ? 1 : 0.4
                onActivated: if (root.player) root.player.next()
            }

            Item { Layout.fillWidth: true }
        }
    }
}
