import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import qs.CustomTheme
import qs.shared

// The time and weather widget that lives on an empty workspace.
//
// It is only on screen while the focused workspace holds no windows: open a
// window, or switch to a workspace that has one, and the whole thing is sucked
// up into the status bar, which takes the clock back over at the same moment.
// Step onto an empty workspace and it pours back out.
//
// The surface itself is never unmapped, for two reasons: Hyprland animates
// layer surfaces as they appear (`layersIn`, a slide), which would fight the
// widget's own animation, and a surface that is mapped last is stacked above
// the bar — the sections have to disappear *underneath* the bar for the suck to
// read properly. It stays mapped and fully transparent instead, with an empty
// input region so clicks land on whatever is behind it.
PanelWindow {
    id: w

    // --- WIRED UP BY shell.qml ---
    // Height of the status bar, so the content clears it and the animation
    // knows where to converge.
    property int barHeight: 36
    // Free-text place name for the forecast, from the bar's settings.
    property string location: "Belfast, UK"
    // Qt date/time formats, kept in step with the bar's own clock.
    property string timeFormat: "HH:mm"
    // Whether the widget is wanted at all (statusbar.json, weather.desktopWidget,
    // toggled on the control centre's Appearance page). Off means it never comes out, so the bar's own
    // clock is never folded away.
    property bool widgetEnabled: true

    // True while the widget is on screen. The bar reads the companion flag
    // below to decide whether to show its own clock.
    readonly property bool shown: _shown
    property bool _shown: false

    // True while the bar should hide its clock, i.e. while this widget is
    // showing the time instead. Dropped the instant the widget starts leaving
    // and only raised once it has nearly finished arriving, so exactly one of
    // the two clocks is legible at any moment.
    readonly property bool hideBarClock: _hideBarClock
    property bool _hideBarClock: false

    // True while any section is still flying. Used to park the weather glyphs'
    // own animations for the duration: every frame of the transition should be
    // spent moving the sections, not redrawing drifting clouds inside them.
    readonly property bool animating: timeSection.running
        || weatherSection.running || forecastSection.running

    // Whether the weather glyphs are allowed to move.
    //
    // Their drifting and falling is the entire idle cost of this widget:
    // measured on this machine, the shell sits at ~1% of a core with them still
    // and ~17% with them running, because any continuous animation keeps the
    // scene graph redrawing at the refresh rate. On a desktop that can be left
    // on an empty workspace for hours — on battery — that is not worth paying
    // for indefinitely, and it leaves nothing spare for the next transition.
    //
    // So they run for a few seconds as the widget arrives, where the movement
    // actually registers, and then settle. Raise motionWindow.interval to keep
    // them going for longer, or set this to `w.shown` for always-on motion.
    property bool glyphMotion: false

    Timer {
        id: motionWindow
        interval: 12000
        onTriggered: w.glyphMotion = false
    }

    WlrLayershell.layer: WlrLayer.Top
    // Kept out of the "quickshell" namespace the bar uses so a layer rule can
    // single this surface out later without touching the bar.
    WlrLayershell.namespace: "ml4w-desktop-widget"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Draws over the reserved strip rather than reserving one of its own.
    exclusionMode: ExclusionMode.Ignore

    color: "transparent"
    // Nothing here is clickable: an empty mask lets every click through to the
    // desktop (and to the bar, which sits in the same strip).
    mask: Region {}

    anchors {
        top: true
        left: true
        right: true
    }

    // Tall enough for the content plus room for the clock's halo to fall.
    //
    // This must not change while the widget is animating. The sections are kept
    // in the layout even when they are invisible for exactly that reason: a
    // section dropping out of the Column would shorten the window, and every
    // height change is a layer-surface reconfigure — a new buffer, a round trip
    // to the compositor, and measurably ~50ms of dropped frames. Three sections
    // appearing one after the other meant three of those, landing right in the
    // middle of the pour-out. That was the stutter.
    implicitHeight: stack.y + stack.implicitHeight + 48

    // The point everything converges on: the middle of the bar, which is where
    // the bar's own clock sits.
    readonly property real funnelX: width / 2
    readonly property real funnelY: barHeight / 2

    // ------------------------------------------------------------------
    // CONTRAST WITH THE WALLPAPER
    // ------------------------------------------------------------------
    // The widget has no background of its own, so its legibility depends
    // entirely on what the wallpaper is doing behind it. The theme's own
    // colours are no help here: matugen derives them from the wallpaper, but
    // the light/dark choice is the user's, so a white wallpaper can perfectly
    // well come with a dark palette whose "on background" colour is near white.
    //
    // The brightness of the wallpaper region actually behind the widget is
    // measured instead, and the text goes black or white to suit. Neutral ink
    // plus an opposite-coloured halo is what survives every wallpaper; theme
    // colours are deliberately not used for the text.
    property real wallpaperLuma: 0.25
    readonly property bool darkInk: wallpaperLuma > 0.56

    readonly property color ink: darkInk ? "#0c1013" : "#ffffff"
    readonly property color inkDim: Qt.rgba(ink.r, ink.g, ink.b, 0.75)
    readonly property color inkFaint: Qt.rgba(ink.r, ink.g, ink.b, 0.55)
    readonly property color haloColor: darkInk ? "#ffffff" : "#000000"

    // The wallpaper ml4w last set. Written on every wallpaper change, so
    // watching it is what keeps the contrast honest.
    FileView {
        id: wallpaperFile
        path: Quickshell.env("HOME") + "/.cache/ml4w/hyprland-dotfiles/current_wallpaper"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: w.sampleWallpaper()
    }

    // Mean brightness of the top-centre of the wallpaper — the part the widget
    // actually covers — rather than of the whole image, which would average a
    // bright sky away against a dark foreground.
    Process {
        id: lumaProc
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(this.text.trim())
                if (!isNaN(v))
                    w.wallpaperLuma = v
            }
        }
    }

    function sampleWallpaper(): void {
        const path = wallpaperFile.text().trim()
        if (path === "")
            return
        lumaProc.command = ["bash", "-c",
            "magick " + JSON.stringify(path)
            + " -gravity North -crop '45%x40%+0+0' +repage"
            + " -colorspace Gray -format '%[fx:mean]' info:"]
        lumaProc.running = false
        lumaProc.running = true
    }

    // ------------------------------------------------------------------
    // WHEN TO SHOW
    // ------------------------------------------------------------------
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    WeatherSource {
        id: weather
        location: w.location
        active: w._shown
        busy: w.animating
    }

    // The workspace on this widget's own monitor, falling back to the focused
    // one before Hyprland has told us about the monitor.
    readonly property var monitor: Hyprland.monitorFor(w.screen)
    readonly property var workspace: monitor && monitor.activeWorkspace
        ? monitor.activeWorkspace : Hyprland.focusedWorkspace

    // A special workspace (the scratchpad) covers the desktop without changing
    // the active workspace, so it has to be tracked separately.
    property bool specialOpen: false

    readonly property bool workspaceEmpty: workspace !== null
        && workspace.toplevels.values.length === 0

    // Beyond the setting, only the workspace decides. A dropped bar panel
    // deliberately does not:
    // the panels are drawn over this surface anyway, and taking the widget away
    // under them made opening the settings or wallpaper panel throw the clock
    // back into the bar and out again.
    readonly property bool wantShown: widgetEnabled && workspaceEmpty && !specialOpen

    // Hyprland fires several events for one action; settle before animating so
    // the widget never flickers on the way between two empty workspaces.
    Timer {
        id: settle
        interval: 70
        onTriggered: w._shown = w.wantShown
    }

    onWantShownChanged: settle.restart()

    Connections {
        target: Hyprland
        function onRawEvent(event): void {
            if (event.name === "activespecial" || event.name === "activespecialv2") {
                // "name,monitor" — an empty name means the special workspace
                // was just closed.
                w.specialOpen = event.data.split(",")[0] !== ""
            }
            if (["openwindow", "closewindow", "movewindow", "movewindowv2",
                 "workspace", "workspacev2", "focusedmon", "focusedmonv2"]
                    .indexOf(event.name) >= 0) {
                Hyprland.refreshToplevels()
                settle.restart()
            }
        }
    }

    Component.onCompleted: {
        Hyprland.refreshToplevels()
        Hyprland.refreshWorkspaces()
        settle.restart()
    }

    // The clock handover. Leaving: the bar's clock is only unfolded once the
    // sections are most of the way into the bar, so the time does not appear
    // twice. Arriving: the bar gives the clock up immediately, so the widget's
    // time is the only one as it lands.
    onShownChanged: {
        if (w.shown) {
            handover.stop()
            w._hideBarClock = true
            // Let the glyphs move while the widget settles in, then go quiet.
            w.glyphMotion = true
            motionWindow.restart()
        } else {
            handover.restart()
            w.glyphMotion = false
            motionWindow.stop()
        }
    }

    Timer {
        id: handover
        interval: 320
        onTriggered: w._hideBarClock = false
    }

    // ------------------------------------------------------------------
    // THE SUCK-IN / POUR-OUT ANIMATION
    // ------------------------------------------------------------------
    // Each section scales about the point where the bar's clock sits. Because
    // that origin is above the section, shrinking also carries it upwards — so
    // one scale does the whole move, and the horizontal axis collapsing faster
    // than the vertical one is what gives it the drawn-into-a-funnel look.
    // Sections are staggered, nearest the bar first, so the widget drains
    // rather than blinking out.
    component Section: Item {
        id: sec

        property bool revealed: false
        property int inDelay: 0
        property int outDelay: 0

        // 0 = fully out on the desktop, 1 = swallowed by the bar.
        property real p: 1

        readonly property bool running: inAnim.running || outAnim.running

        // Distance from this section's own top to the funnel point.
        readonly property real funnelOffset: w.funnelY - (stack.y + sec.y)

        width: stack.width
        // Never taken out of the layout, only faded out: see the window's
        // implicitHeight above. A fully transparent subtree is skipped by the
        // renderer anyway, so this costs nothing while the widget is away.
        opacity: Math.max(0, Math.min(1, 1.3 - 1.3 * sec.p))

        transform: Scale {
            origin.x: sec.width / 2
            origin.y: sec.funnelOffset
            xScale: 1 - sec.p * 0.97
            yScale: 1 - sec.p
        }

        onRevealedChanged: {
            if (sec.revealed) {
                outAnim.stop()
                inAnim.restart()
            } else {
                inAnim.stop()
                outAnim.restart()
            }
        }

        SequentialAnimation {
            id: inAnim
            PauseAnimation { duration: sec.inDelay }
            NumberAnimation {
                target: sec; property: "p"; to: 0
                duration: 520
                easing.type: Easing.OutBack
                easing.overshoot: 1.15
            }
        }

        SequentialAnimation {
            id: outAnim
            PauseAnimation { duration: sec.outDelay }
            NumberAnimation {
                target: sec; property: "p"; to: 1
                duration: 430
                easing.type: Easing.InBack
                easing.overshoot: 0.8
            }
        }
    }

    // The wind dart, pointing the way an aviation wind barb does: along the
    // bearing the wind is blowing *from*, which is the direction a METAR
    // reports. A southerly therefore points down the screen, towards the south
    // it is coming out of.
    component WindArrow: Shape {
        id: arrow

        property real bearing: 0
        property real glyphSize: 12

        implicitWidth: glyphSize
        implicitHeight: glyphSize
        // The default renderer is enough for a four-line dart and costs less to
        // rasterise than the curve renderer.
        preferredRendererType: Shape.GeometryRenderer

        transform: Rotation {
            origin.x: arrow.glyphSize / 2
            origin.y: arrow.glyphSize / 2
            angle: arrow.bearing
        }

        // Drawn pointing straight up, i.e. due north before the rotation.
        ShapePath {
            fillColor: w.inkDim
            strokeWidth: -1
            startX: arrow.glyphSize * 0.5; startY: 0
            PathLine { x: arrow.glyphSize * 0.95; y: arrow.glyphSize }
            PathLine { x: arrow.glyphSize * 0.5;  y: arrow.glyphSize * 0.7 }
            PathLine { x: arrow.glyphSize * 0.05; y: arrow.glyphSize }
            PathLine { x: arrow.glyphSize * 0.5;  y: 0 }
        }
    }

    // Text that carries its own contrast. The outline is drawn by the text
    // shader itself, so — unlike a blurred drop shadow — it needs no offscreen
    // layer and costs nothing per frame. That matters because the weather
    // glyphs animate continuously: anything sharing a layer with them would be
    // re-rendered, and re-blurred, on every single frame.
    component InkText: Text {
        color: w.ink
        font.family: "Red Hat Display"
        font.weight: Font.Medium
        style: Text.Outline
        styleColor: w.haloColor
    }

    // ------------------------------------------------------------------
    // CONTENT
    // ------------------------------------------------------------------
    Column {
        id: stack

        anchors.horizontalCenter: parent.horizontalCenter
        y: w.barHeight + 20
        width: 560
        spacing: 22

        // --- 1. TIME AND DATE ---
        // This is the one section that keeps a blurred halo: its content only
        // changes once a minute, so the layer is generated once and then simply
        // re-used, which is cheap even while the section is flying.
        Section {
            id: timeSection
            revealed: w.shown
            inDelay: 0
            outDelay: 0
            implicitHeight: timeCol.height

            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: w.haloColor
                shadowOpacity: w.darkInk ? 0.5 : 0.62
                shadowBlur: 0.9
                shadowVerticalOffset: 1
            }

            Column {
                id: timeCol
                width: parent.width
                spacing: 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(clock.date, w.timeFormat)
                    color: w.ink
                    font.family: "Red Hat Display"
                    font.pixelSize: 92
                    font.weight: Font.Medium
                    font.letterSpacing: -1
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(clock.date, "dddd, d MMMM").toUpperCase()
                    color: w.inkDim
                    font.family: "Red Hat Display"
                    font.pixelSize: 17
                    font.weight: Font.Medium
                    font.letterSpacing: 4
                }
            }
        }

        // --- 2. CURRENT WEATHER ---
        Section {
            id: weatherSection
            revealed: w.shown
            inDelay: 90
            outDelay: 80
            implicitHeight: weatherCol.height + 6

            Column {
                id: weatherCol
                width: parent.width
                spacing: 8

                // Where the reading is for, as the control centre labels it. Read
                // only: the place is changed in the control centre or the settings.
                // Its height is fixed so the geocoder answering never resizes the
                // window (see implicitHeight above).
                InkText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 16
                    verticalAlignment: Text.AlignVCenter
                    text: (weather.place !== "" ? weather.place : w.location).toUpperCase()
                    color: w.inkFaint
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.letterSpacing: 2
                }

                // The reading and the detail block are laid out as one row and that
                // row is centred, so what lands on the widget's centre line is the
                // gap between them rather than either block.
                Row {
                    id: weatherRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 34

                    // Icon and temperature.
                    Row {
                        id: nowRow
                        spacing: 14

                        WeatherIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 84
                            code: weather.code
                            night: !weather.isDay
                            // Parked while a section is in flight, so the transition
                            // gets the whole frame budget, and again once the
                            // arrival has had its moment of movement.
                            animate: w.glyphMotion && !w.animating
                            // Monochrome: the palette's own accent is derived from
                            // the wallpaper and can land at any brightness, which is
                            // the one thing this surface cannot afford.
                            warm: w.ink
                            cool: w.inkDim
                            opacity: weather.loaded ? 1 : 0.4
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: -2

                            InkText {
                                text: weather.loaded ? weather.fmt(weather.temperature) : "--°"
                                font.pixelSize: 58
                            }

                            InkText {
                                text: weather.error !== "" ? weather.error
                                    : (weather.loaded ? conditionGlyph.label : "Loading…")
                                color: w.inkDim
                                font.pixelSize: 15
                                font.letterSpacing: 0.5
                            }
                        }
                    }

                    // Today's range and the rest of the readings, sitting to the
                    // right of the reading and level with the top of it.
                    GridLayout {
                        id: detailGrid
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 2

                        component DetailLabel: InkText {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            color: w.inkFaint
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 1
                        }

                        component DetailValue: InkText {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            color: w.inkDim
                            font.pixelSize: 15
                        }

                        DetailLabel { text: "MIN / MAX" }
                        DetailValue {
                            text: weather.loaded
                                ? weather.fmt(weather.todayMin) + " / " + weather.fmt(weather.todayMax)
                                : "--° / --°"
                            color: w.ink
                        }

                        DetailLabel { text: "HUMIDITY" }
                        DetailValue { text: weather.loaded ? weather.humidity + "%" : "--%" }

                        DetailLabel { text: "FEELS LIKE" }
                        DetailValue { text: weather.loaded ? weather.fmt(weather.apparent) : "--°" }

                        RowLayout {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            spacing: 5

                            WindArrow {
                                Layout.alignment: Qt.AlignVCenter
                                glyphSize: 11
                                bearing: weather.windDirection
                                opacity: weather.loaded ? 1 : 0
                            }

                            DetailLabel { text: "WIND" }
                        }
                        DetailValue { text: weather.loaded ? weather.windMetar : "--" }

                        DetailLabel { text: "QNH" }
                        DetailValue {
                            text: weather.loaded ? Math.round(weather.pressure) + " hPa" : "--"
                        }
                    }
                }
            }

            // The condition wording lives on the icon, so a hidden instance
            // lends its label rather than the mapping being written out twice.
            WeatherIcon {
                id: conditionGlyph
                visible: false
                animate: false
                code: weather.code
            }
        }

        // --- 3. THREE DAY FORECAST ---
        Section {
            id: forecastSection
            revealed: w.shown
            inDelay: 180
            outDelay: 160
            implicitHeight: forecastRow.height

            Row {
                id: forecastRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 54

                Repeater {
                    model: weather.forecast

                    Column {
                        required property var modelData
                        spacing: 2

                        InkText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.day.toUpperCase()
                            color: w.inkFaint
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            font.letterSpacing: 2
                        }

                        WeatherIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            size: 42
                            code: modelData.code
                            animate: w.glyphMotion && !w.animating
                            warm: w.ink
                            cool: w.inkDim
                        }

                        InkText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: weather.fmt(modelData.min) + " / " + weather.fmt(modelData.max)
                            color: w.inkDim
                            font.pixelSize: 14
                        }
                    }
                }
            }
        }
    }
}
