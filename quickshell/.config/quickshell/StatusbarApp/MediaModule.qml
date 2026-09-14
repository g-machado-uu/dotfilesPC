import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.shared

// Now playing, in the bar. Shows a play/pause glyph and the track title, and
// folds out of the layout entirely when nothing is playing — the same
// `collapsed` convention the updates and battery modules use, so the bar's
// keyboard navigation rebuilds around it.
Rectangle {
    id: media

    // The player to follow: the first one that is actually playing, otherwise
    // the first that exists at all, so a paused player stays reachable.
    readonly property var player: {
        let list = Mpris.players.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].isPlaying)
                return list[i]
        }
        return list.length > 0 ? list[0] : null
    }

    readonly property bool collapsed: media.player === null
    // Set by the keyboard navigation in StatusbarWindow.
    property bool focused: false

    readonly property string title: {
        if (!media.player)
            return ""
        if (media.player.trackTitle)
            return media.player.trackTitle
        return media.player.identity ? media.player.identity : "Playing"
    }

    signal clicked()
    function activate(): void { media.clicked() }

    // The bar opens the media panel after the pointer rests here for a moment.
    readonly property bool hovered: mouseArea.containsMouse
    readonly property bool active: mouseArea.containsMouse || media.focused

    visible: !collapsed
    implicitWidth: collapsed ? 0 : row.implicitWidth + 20
    implicitHeight: 30
    radius: 15

    color: media.active ? Theme.primary : "transparent"
    Behavior on color {
        ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7

        IconGlyph {
            Layout.alignment: Qt.AlignVCenter
            source: (media.player && media.player.isPlaying)
                ? "../shared/icons/play.svg"
                : "../shared/icons/pause.svg"
            size: 13
            color: media.active ? Theme.background : Theme.primary
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            // Long titles are cut rather than allowed to push the bar wider.
            Layout.maximumWidth: 150
            text: media.title
            elide: Text.ElideRight
            color: media.active ? Theme.background : Theme.primary
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: media.clicked()
        // Scrolling over the module steps through tracks without opening it.
        onWheel: wheel => {
            if (!media.player)
                return
            if (wheel.angleDelta.y > 0)
                media.player.previous()
            else
                media.player.next()
        }
    }
}
