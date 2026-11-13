import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.shared

// Now playing, in the bar. Shows a play/pause glyph and the track title.
//
// The slot is a fixed width and is always there, whether or not anything is
// playing: the title is elided into a constant text box and the whole module
// keeps its width when the last player goes away, so neither a track change
// nor a player appearing or disappearing ever resizes the bar. With no player
// it holds a dimmed music glyph rather than an empty gap.
//
// It still reports `collapsed` while there is no player, which is what keeps it
// out of the bar's keyboard navigation (an empty media panel is not worth a
// stop) — unlike the updates and battery modules, that flag no longer takes it
// out of the layout.
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

    // Width of the title box. The module's own width is built from it, so the
    // two can never drift apart.
    property real titleWidth: 150

    // No gap in front of this module: it is a wide pill whose ink starts 10px
    // inside its own left edge, so the bar's usual 7px either side on top of
    // that read as a hole between it and the terminal button. Read by the bar's
    // left area.
    readonly property real gapBefore: 0
    // Skipped by the bar's keyboard navigation while nothing is playing. It
    // keeps its place in the layout regardless; see the note above.
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
    // Only ever true with a player: there is nothing to show without one.
    readonly property bool hovered: mouseArea.containsMouse && !media.collapsed
    readonly property bool active: media.hovered || (media.focused && !media.collapsed)

    // A constant width: glyph, gap, title box, and the padding either side.
    implicitWidth: 13 + row.spacing + media.titleWidth + 20
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
            source: media.collapsed
                ? "../shared/icons/music.svg"
                : ((media.player && media.player.isPlaying)
                    ? "../shared/icons/play.svg"
                    : "../shared/icons/pause.svg")
            size: 13
            color: media.active ? Theme.background : Theme.primary
            // Dimmed while the slot is only holding its place.
            opacity: media.collapsed ? 0.35 : 1
            Behavior on opacity {
                NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
            }
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            // A fixed slot: long titles are cut and short ones leave room, so
            // a track change never resizes the bar.
            Layout.preferredWidth: media.titleWidth
            Layout.maximumWidth: media.titleWidth
            text: media.title
            elide: Text.ElideRight
            color: media.active ? Theme.background : Theme.primary
            font.family: Theme.fontFamily
            font.pixelSize: 12
            opacity: media.collapsed ? 0 : 1
            Behavior on opacity {
                NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        // Nothing to click or scroll through without a player.
        enabled: !media.collapsed
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
