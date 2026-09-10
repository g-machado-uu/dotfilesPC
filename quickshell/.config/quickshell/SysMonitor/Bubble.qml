import QtQuick
import QtQuick.Shapes

// One floating "bubble" gauge.
//
// Everything visual lives inside `content`, which is rendered once into a
// cached layer. The idle float/scale animations then only move a textured
// quad around instead of re-rasterising arcs and text every frame.
Item {
    id: bubble

    // --- injected by the parent ---
    required property var pal          // matugen palette (see shell.qml)
    required property int index        // stagger order
    required property int total        // how many bubbles exist
    property real diameter: 170
    property string label: ""
    property real value: 0             // 0..1 -> gauge fill
    property string readout: "--"      // big number
    property string unit: ""
    property string detail: ""
    property string sub: ""

    // "gauge"  -> speedometer arc + big readout
    // "thermo" -> a pair of thermometers (CPU / GPU)
    property string mode: "gauge"
    property real tempA: 0
    property real tempAMax: 100
    property string labelA: "CPU"
    property real tempB: 0
    property real tempBMax: 95
    property string labelB: "GPU"
    property real baseOffset: 0        // resting vertical offset inside the row

    // --- animation state ---
    property real formScale: 0.15
    property real riseY: 90
    property real floatY: 0
    property real driftX: 0

    readonly property real pad: diameter * 0.14

    implicitWidth: diameter + pad * 2
    implicitHeight: diameter + pad * 2

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: baseOffset

    opacity: 0
    transformOrigin: Item.Center

    // The per-frame motion goes through transforms rather than anchors, so a
    // drifting bubble never invalidates the row layout.
    transform: [
        Translate { x: bubble.driftX; y: bubble.riseY + bubble.floatY },
        Scale {
            origin.x: bubble.width / 2; origin.y: bubble.height / 2
            xScale: bubble.formScale; yScale: bubble.formScale
        }
    ]

    // ---------- geometry ----------
    readonly property real ringRadius: diameter / 2 - diameter * 0.085
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real arcStart: 135
    readonly property real arcSweep: 270

    // smoothed value, so the needle sweeps instead of snapping
    property real shown: 0
    onValueChanged: shown = Math.max(0, Math.min(1, value))
    Behavior on shown { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }

    // calm -> warm -> alarming, straight out of the matugen palette
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

    readonly property color accent: ramp(shown)

    function pointAt(frac, radius) {
        const a = (arcStart + arcSweep * frac) * Math.PI / 180;
        return Qt.point(cx + radius * Math.cos(a), cy + radius * Math.sin(a));
    }

    Item {
        id: content
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true

        // ---------- halo ----------
        Rectangle {
            anchors.centerIn: parent
            width: bubble.diameter * 1.13
            height: width
            radius: width / 2
            color: Qt.rgba(bubble.accent.r, bubble.accent.g, bubble.accent.b, 0.10 + 0.12 * bubble.shown)
            Behavior on color { ColorAnimation { duration: 500 } }
        }

        // ---------- glass body ----------
        Rectangle {
            anchors.centerIn: parent
            width: bubble.diameter
            height: width
            radius: width / 2
            color: Qt.rgba(bubble.pal.surface_container.r, bubble.pal.surface_container.g,
                           bubble.pal.surface_container.b, 0.96)
            border.width: 1
            border.color: Qt.rgba(bubble.pal.outline.r, bubble.pal.outline.g, bubble.pal.outline.b, 0.42)

            // soap-film sheen
            Rectangle {
                width: parent.width * 0.42
                height: parent.height * 0.24
                radius: height / 2
                x: parent.width * 0.16
                y: parent.height * 0.11
                rotation: -28
                color: Qt.rgba(1, 1, 1, 0.055)
            }
            Rectangle {
                width: parent.width * 0.10
                height: width
                radius: width / 2
                x: parent.width * 0.70
                y: parent.height * 0.74
                color: Qt.rgba(1, 1, 1, 0.035)
            }
        }

        // ---------- speedometer ticks ----------
        Repeater {
            model: bubble.mode === "gauge" ? 25 : 0
            Rectangle {
                readonly property real frac: index / 24
                readonly property bool major: index % 6 === 0
                width: major ? 2.2 : 1.4
                height: major ? bubble.diameter * 0.055 : bubble.diameter * 0.032
                radius: width / 2
                color: bubble.shown >= frac - 0.001
                       ? Qt.rgba(bubble.accent.r, bubble.accent.g, bubble.accent.b, major ? 0.95 : 0.7)
                       : Qt.rgba(bubble.pal.outline.r, bubble.pal.outline.g, bubble.pal.outline.b, major ? 0.45 : 0.28)
                Behavior on color { ColorAnimation { duration: 260 } }
                transform: [
                    Translate {
                        x: bubble.cx - width / 2
                        y: bubble.cy - bubble.ringRadius - height / 2 - bubble.diameter * 0.055
                    },
                    Rotation {
                        origin.x: bubble.cx
                        origin.y: bubble.cy
                        angle: -135 + 270 * frac
                    }
                ]
            }
        }

        // ---------- gauge arcs ----------
        Shape {
            anchors.fill: parent
            visible: bubble.mode === "gauge"
            preferredRendererType: Shape.CurveRenderer

            ShapePath {   // track
                strokeColor: Qt.rgba(bubble.pal.outline_variant.r, bubble.pal.outline_variant.g,
                                     bubble.pal.outline_variant.b, 0.9)
                strokeWidth: bubble.diameter * 0.055
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: bubble.cx; centerY: bubble.cy
                    radiusX: bubble.ringRadius; radiusY: bubble.ringRadius
                    startAngle: bubble.arcStart; sweepAngle: bubble.arcSweep
                }
            }

            ShapePath {   // progress
                strokeColor: bubble.accent
                strokeWidth: bubble.diameter * 0.055
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: bubble.cx; centerY: bubble.cy
                    radiusX: bubble.ringRadius; radiusY: bubble.ringRadius
                    startAngle: bubble.arcStart
                    sweepAngle: Math.max(0.01, bubble.arcSweep * bubble.shown)
                }
            }
        }

        // ---------- knob riding the arc ----------
        Rectangle {
            visible: bubble.mode === "gauge"
            readonly property point p: bubble.pointAt(bubble.shown, bubble.ringRadius)
            width: bubble.diameter * 0.082
            height: width
            radius: width / 2
            x: p.x - width / 2
            y: p.y - height / 2
            color: bubble.pal.surface_container_lowest
            border.width: Math.max(2, bubble.diameter * 0.018)
            border.color: bubble.accent
        }

        // ---------- readout ----------
        Column {
            visible: bubble.mode === "gauge"
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -bubble.diameter * 0.04
            spacing: bubble.diameter * 0.012

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 1
                Text {
                    text: bubble.readout
                    color: bubble.pal.on_surface
                    font.family: bubble.pal.fontFamily
                    font.pixelSize: bubble.diameter * 0.245
                    font.weight: Font.DemiBold
                }
                Text {
                    text: bubble.unit
                    color: Qt.rgba(bubble.pal.on_surface_variant.r, bubble.pal.on_surface_variant.g,
                                   bubble.pal.on_surface_variant.b, 0.9)
                    font.family: bubble.pal.fontFamily
                    font.pixelSize: bubble.diameter * 0.105
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: bubble.diameter * 0.055
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: bubble.label
                color: bubble.accent
                font.family: bubble.pal.fontFamily
                font.pixelSize: bubble.diameter * 0.082
                font.letterSpacing: bubble.diameter * 0.012
                font.weight: Font.DemiBold
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: bubble.detail
                color: bubble.pal.on_surface_variant
                font.family: bubble.pal.fontFamily
                font.pixelSize: bubble.diameter * 0.075
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: bubble.sub
                visible: text !== ""
                color: Qt.rgba(bubble.pal.on_surface_variant.r, bubble.pal.on_surface_variant.g,
                               bubble.pal.on_surface_variant.b, 0.62)
                font.family: bubble.pal.fontFamily
                font.pixelSize: bubble.diameter * 0.066
            }
        }
        // ---------- thermometer pair (mode: "thermo") ----------
        Item {
            visible: bubble.mode === "thermo"
            anchors.centerIn: parent
            width: parent.width
            height: parent.height

            Text {
                id: thermoTitle
                anchors.horizontalCenter: parent.horizontalCenter
                y: bubble.cy - bubble.diameter * 0.42
                text: bubble.label
                color: bubble.pal.on_surface_variant
                font.family: bubble.pal.fontFamily
                font.pixelSize: bubble.diameter * 0.078
                font.letterSpacing: bubble.diameter * 0.014
                font.weight: Font.DemiBold
            }

            Row {
                id: thermoRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: thermoTitle.bottom
                anchors.topMargin: bubble.diameter * 0.02
                spacing: bubble.diameter * 0.10

                Thermometer {
                    pal: bubble.pal
                    unitSize: bubble.diameter
                    label: bubble.labelA
                    temp: bubble.tempA
                    maxTemp: bubble.tempAMax
                    col: bubble.ramp((bubble.tempA - 20) / (bubble.tempAMax - 20))
                }
                Thermometer {
                    pal: bubble.pal
                    unitSize: bubble.diameter
                    label: bubble.labelB
                    temp: bubble.tempB
                    maxTemp: bubble.tempBMax
                    col: bubble.ramp((bubble.tempB - 20) / (bubble.tempBMax - 20))
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: thermoRow.bottom
                anchors.topMargin: bubble.diameter * 0.015
                text: bubble.detail
                color: Qt.rgba(bubble.pal.on_surface_variant.r, bubble.pal.on_surface_variant.g,
                               bubble.pal.on_surface_variant.b, 0.7)
                font.family: bubble.pal.fontFamily
                font.pixelSize: bubble.diameter * 0.068
            }
        }
    }

    // ---------- formation ripple (outside the cached layer: it animates) ----------
    Rectangle {
        id: ripple
        anchors.centerIn: parent
        width: bubble.diameter
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: bubble.accent
        opacity: 0
        visible: opacity > 0
    }

    // clicks on a bubble must not dismiss the panel
    MouseArea {
        anchors.fill: parent
        onClicked: {}
    }

    // ---------- animations ----------
    SequentialAnimation {
        id: formAnim
        running: true
        PauseAnimation { duration: bubble.index * 85 }
        ParallelAnimation {
            NumberAnimation { target: bubble; property: "formScale"; from: 0.12; to: 1
                              duration: 780; easing.type: Easing.OutBack; easing.overshoot: 1.45 }
            NumberAnimation { target: bubble; property: "opacity"; from: 0; to: 1
                              duration: 420; easing.type: Easing.OutQuad }
            NumberAnimation { target: bubble; property: "riseY"; to: 0
                              duration: 820; easing.type: Easing.OutCubic }
            SequentialAnimation {
                NumberAnimation { target: ripple; property: "opacity"; to: 0.55; duration: 120 }
                ParallelAnimation {
                    NumberAnimation { target: ripple; property: "scale"; from: 1; to: 1.35
                                      duration: 720; easing.type: Easing.OutQuad }
                    NumberAnimation { target: ripple; property: "opacity"; to: 0; duration: 720 }
                }
            }
        }
        ScriptAction { script: floatAnim.start() }
    }

    SequentialAnimation {
        id: floatAnim
        loops: Animation.Infinite
        NumberAnimation { target: bubble; property: "floatY"; to: -7 - bubble.index % 3
                          duration: 2400 + bubble.index * 260; easing.type: Easing.InOutSine }
        NumberAnimation { target: bubble; property: "floatY"; to: 0
                          duration: 2400 + bubble.index * 260; easing.type: Easing.InOutSine }
    }

    // drift up and out of sight
    function dismiss() {
        floatAnim.stop();
        formAnim.stop();
        awayAnim.start();
    }

    SequentialAnimation {
        id: awayAnim
        PauseAnimation { duration: (bubble.total - 1 - bubble.index) * 55 }
        ParallelAnimation {
            NumberAnimation { target: bubble; property: "riseY"; to: -170 - bubble.index * 22
                              duration: 720; easing.type: Easing.InQuad }
            NumberAnimation { target: bubble; property: "driftX"
                              to: (bubble.index % 2 === 0 ? -1 : 1) * (26 + bubble.index * 7)
                              duration: 720; easing.type: Easing.InOutSine }
            NumberAnimation { target: bubble; property: "formScale"; to: 0.45
                              duration: 720; easing.type: Easing.InCubic }
            NumberAnimation { target: bubble; property: "opacity"; to: 0
                              duration: 700; easing.type: Easing.InQuad }
        }
    }
}
