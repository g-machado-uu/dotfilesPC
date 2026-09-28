import QtQuick

// Per-core load, opened by clicking the CPU bubble.
//
// Deliberately bars rather than gauges: this has to stay readable when the
// machine has 128 threads, and 128 speedometers would be noise. The grid
// reshapes itself around the core count -- one row of wide, labelled bars on
// an 8-thread desktop, a dense 16-wide block on a Threadripper.
Item {
    id: panel

    required property var pal
    property var cores: []          // array of 0..1, one entry per thread
    property bool open: false
    signal closeRequested()

    // when >= 0 the card is placed so its right edge lands here, which is how
    // the shell parks it alongside the bubble row; otherwise it centres
    property real cardRightEdge: -1
    readonly property real cardWidth: card.width
    readonly property real cardHeight: card.height
    readonly property bool cardHovered: cardHover.containsMouse

    readonly property int n: cores.length
    readonly property int columns: n <= 8 ? Math.max(1, n) : (n <= 32 ? 8 : 16)
    readonly property int rows: Math.max(1, Math.ceil(n / columns))

    // bars thin out and lose their labels as the core count climbs
    readonly property bool showLabels: n <= 32
    readonly property real cellW: n <= 16 ? 34 : (n <= 64 ? 26 : 20)
    readonly property real barH: rows <= 2 ? 100 : (rows <= 4 ? 78 : 58)
    readonly property real gap: n <= 64 ? 6 : 4
    readonly property real padding: 26

    readonly property real avg: {
        if (n === 0) return 0;
        let s = 0;
        for (let i = 0; i < n; i++) s += cores[i];
        return s / n;
    }

    // same calm -> warm -> alarming ramp the bubbles use
    function ramp(f) {
        const p = pal.primary, t = pal.tertiary, e = pal.error;
        f = Math.max(0, Math.min(1, f));
        if (f < 0.55) return Qt.rgba(p.r, p.g, p.b, 1);
        if (f < 0.85) {
            const k = (f - 0.55) / 0.30;
            return Qt.rgba(p.r + (t.r - p.r) * k, p.g + (t.g - p.g) * k, p.b + (t.b - p.b) * k, 1);
        }
        const k2 = Math.min(1, (f - 0.85) / 0.15);
        return Qt.rgba(t.r + (e.r - t.r) * k2, t.g + (e.g - t.g) * k2, t.b + (e.b - t.b) * k2, 1);
    }

    opacity: 0
    visible: opacity > 0
    onOpenChanged: opacity = open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

    // catches clicks that miss the card; the bubbles behind are faded by the
    // shell rather than covered, since a dim layer could only reach as far as
    // this window and would draw a hard rectangle edge across the desktop
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: panel.closeRequested()
    }

    Rectangle {
        id: card
        x: panel.cardRightEdge >= 0 ? panel.cardRightEdge - width
                                    : (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: grid.width + panel.padding * 2
        height: header.height + grid.height + footer.height + panel.padding * 2 + 26
        radius: 28
        color: Qt.rgba(panel.pal.surface_container.r, panel.pal.surface_container.g,
                       panel.pal.surface_container.b, 0.98)
        border.width: 1
        border.color: Qt.rgba(panel.pal.outline.r, panel.pal.outline.g, panel.pal.outline.b, 0.45)

        scale: panel.open ? 1 : 0.9
        Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

        // clicks on the card itself must not close it, and hovering it keeps
        // the panel alive after the pointer leaves the bubble
        MouseArea {
            id: cardHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: {}
        }

        Item {
            id: header
            x: panel.padding
            y: panel.padding
            width: grid.width
            height: 22

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "PER-CORE LOAD"
                color: panel.pal.primary
                font.family: panel.pal.fontFamily
                font.pixelSize: 13
                font.letterSpacing: 1.6
                font.weight: Font.DemiBold
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: panel.n + " threads  ·  avg " + Math.round(panel.avg * 100) + "%"
                color: panel.pal.on_surface_variant
                font.family: panel.pal.fontFamily
                font.pixelSize: 12
            }
        }

        Grid {
            id: grid
            x: panel.padding
            y: header.y + header.height + 16
            columns: panel.columns
            spacing: panel.gap

            Repeater {
                model: panel.n

                Column {
                    id: cell
                    required property int index
                    readonly property real frac: Math.max(0, Math.min(1, panel.cores[index] || 0))
                    spacing: 4

                    Rectangle {
                        width: panel.cellW
                        height: panel.barH
                        radius: Math.min(5, panel.cellW * 0.22)
                        color: Qt.rgba(panel.pal.outline_variant.r, panel.pal.outline_variant.g,
                                       panel.pal.outline_variant.b, 0.55)

                        Rectangle {
                            id: fill
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            radius: parent.radius
                            // a sliver always shows, so an idle core still reads as a core
                            property real shown: cell.frac
                            Behavior on shown { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                            height: Math.max(3, shown * parent.height)
                            color: panel.ramp(shown)
                        }
                    }

                    Text {
                        visible: panel.showLabels
                        width: panel.cellW
                        horizontalAlignment: Text.AlignHCenter
                        text: cell.index
                        color: Qt.rgba(panel.pal.on_surface_variant.r, panel.pal.on_surface_variant.g,
                                       panel.pal.on_surface_variant.b, 0.65)
                        font.family: panel.pal.fontFamily
                        font.pixelSize: 10
                    }
                }
            }
        }

        Text {
            id: footer
            x: panel.padding
            y: grid.y + grid.height + 14
            width: grid.width
            horizontalAlignment: Text.AlignHCenter
            text: "Esc or click outside to close"
            color: Qt.rgba(panel.pal.on_surface_variant.r, panel.pal.on_surface_variant.g,
                           panel.pal.on_surface_variant.b, 0.5)
            font.family: panel.pal.fontFamily
            font.pixelSize: 11
        }
    }
}
