import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.CustomTheme

// An animated weather glyph for a WMO weather code, drawn rather than loaded so
// it follows the wallpaper colours like everything else in the bar and can move
// — the sun turns, clouds drift, rain and snow fall, lightning flashes.
//
// WMO codes are what Open-Meteo returns; they are bucketed into the handful of
// conditions worth drawing separately.
Item {
    id: icon

    property int code: 0
    // Night swaps the sun for a moon.
    property bool night: false
    property real size: 46
    // Animations are cheap but pointless off screen; the panel switches this
    // off when it is closed.
    property bool animate: true

    property color warm: Theme.primary
    property color cool: Theme.on_background

    implicitWidth: size
    implicitHeight: size

    readonly property string kind: {
        const c = icon.code
        if (c === 0) return "clear"
        if (c === 1 || c === 2) return "partly"
        if (c === 3) return "cloudy"
        if (c === 45 || c === 48) return "fog"
        if (c >= 51 && c <= 57) return "drizzle"
        if ((c >= 61 && c <= 67) || (c >= 80 && c <= 82)) return "rain"
        if ((c >= 71 && c <= 77) || c === 85 || c === 86) return "snow"
        if (c >= 95) return "thunder"
        return "cloudy"
    }

    // Human-readable condition, used as the caption next to the temperature.
    readonly property string label: {
        const c = icon.code
        if (c === 0) return "Clear"
        if (c === 1) return "Mainly clear"
        if (c === 2) return "Partly cloudy"
        if (c === 3) return "Overcast"
        if (c === 45 || c === 48) return "Fog"
        if (c >= 51 && c <= 57) return "Drizzle"
        if (c >= 61 && c <= 65) return "Rain"
        if (c === 66 || c === 67) return "Freezing rain"
        if (c >= 71 && c <= 75) return "Snow"
        if (c === 77) return "Snow grains"
        if (c >= 80 && c <= 82) return "Showers"
        if (c === 85 || c === 86) return "Snow showers"
        if (c === 95) return "Thunderstorm"
        if (c >= 96) return "Thunderstorm, hail"
        return "Unknown"
    }

    readonly property bool hasCloud: kind !== "clear" && kind !== "fog"
    readonly property bool hasSun: kind === "clear" || kind === "partly"

    // ---- Sun: a disc with rays that turn slowly. ----
    Item {
        id: sun
        visible: icon.hasSun && !icon.night
        width: icon.size * (icon.kind === "clear" ? 0.62 : 0.46)
        height: width
        x: icon.kind === "clear" ? (icon.size - width) / 2 : icon.size * 0.02
        y: icon.kind === "clear" ? (icon.size - height) / 2 : icon.size * 0.04

        Item {
            id: rays
            anchors.fill: parent
            Repeater {
                model: 8
                Rectangle {
                    required property int index
                    width: sun.width * 0.09
                    height: sun.width * 0.2
                    radius: width / 2
                    color: icon.warm
                    x: sun.width / 2 - width / 2
                    y: -sun.width * 0.1
                    transform: Rotation {
                        origin.x: sun.width * 0.045
                        origin.y: sun.width * 0.6
                        angle: index * 45
                    }
                }
            }
            RotationAnimation on rotation {
                from: 0; to: 360
                duration: 28000
                loops: Animation.Infinite
                running: sun.visible && icon.animate
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: sun.width * 0.58
            height: width
            radius: width / 2
            color: icon.warm
        }
    }

    // ---- Moon: the night stand-in for the sun. ----
    // The crescent is masked out of the disc rather than painted over with a
    // second circle in the background colour: the desktop widget has no
    // background to match, so an opaque bite would show as a dark blob sitting
    // on the wallpaper.
    Item {
        id: moon
        visible: icon.hasSun && icon.night
        width: sun.width
        height: sun.height
        x: sun.x
        y: sun.y

        // The full disc, drawn into a layer so it can be masked.
        Item {
            id: moonDisc
            anchors.fill: parent
            visible: false
            layer.enabled: true

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.8
                height: width
                radius: width / 2
                color: icon.warm
            }
        }

        // The offset circle that gets taken out of it. Only its alpha matters.
        Item {
            id: moonBite
            anchors.fill: parent
            visible: false
            layer.enabled: true

            Rectangle {
                width: moon.width * 0.8
                height: width
                radius: width / 2
                color: "black"
                x: moon.width * 0.1 + width * 0.3
                y: moon.height * 0.1 - width * 0.22
            }
        }

        MultiEffect {
            anchors.fill: parent
            source: moonDisc
            maskEnabled: true
            maskSource: moonBite
            maskInverted: true
            maskThresholdMin: 0.5
        }
    }

    // ---- Cloud: three lobes over a rounded base, drifting sideways. ----
    component Cloud: Item {
        id: cloud
        property color tint: icon.cool
        property real span: icon.size * 0.72
        property int driftDuration: 5200
        width: span
        height: span * 0.6

        Rectangle {
            x: 0; y: cloud.height * 0.42
            width: cloud.width; height: cloud.height * 0.58
            radius: height / 2
            color: cloud.tint
        }
        Rectangle {
            x: cloud.width * 0.08; y: cloud.height * 0.16
            width: cloud.width * 0.42; height: width
            radius: width / 2
            color: cloud.tint
        }
        Rectangle {
            x: cloud.width * 0.42; y: 0
            width: cloud.width * 0.52; height: width
            radius: width / 2
            color: cloud.tint
        }

        SequentialAnimation on x {
            running: cloud.visible && icon.animate
            loops: Animation.Infinite
            NumberAnimation {
                to: cloud.x + icon.size * 0.05
                duration: cloud.driftDuration
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: cloud.x
                duration: cloud.driftDuration
                easing.type: Easing.InOutSine
            }
        }
    }

    Cloud {
        id: mainCloud
        visible: icon.hasCloud
        opacity: 0.92
        x: icon.kind === "partly" ? icon.size * 0.24 : (icon.size - width) / 2
        y: icon.kind === "partly" ? icon.size * 0.3
            : (icon.kind === "cloudy" ? icon.size * 0.24 : icon.size * 0.1)
    }

    // A second, dimmer cloud behind the first for plain overcast.
    Cloud {
        visible: icon.kind === "cloudy"
        span: icon.size * 0.5
        tint: icon.cool
        opacity: 0.45
        driftDuration: 7000
        x: icon.size * 0.04
        y: icon.size * 0.1
        z: -1
    }

    // ---- Falling precipitation, staggered so the drops do not march. ----
    component Fall: Item {
        id: fall
        property int count: 3
        property bool flake: false
        property real dropWidth: icon.size * 0.075
        property real dropHeight: icon.size * (flake ? 0.075 : 0.17)
        property real travel: icon.size * 0.22
        property int period: flake ? 2600 : 1250

        anchors.fill: parent

        Repeater {
            model: fall.count
            Rectangle {
                required property int index
                width: fall.dropWidth
                height: fall.dropHeight
                radius: width / 2
                color: icon.warm
                x: icon.size * (0.26 + index * 0.19)
                y: icon.size * 0.62
                opacity: 0

                SequentialAnimation {
                    running: fall.visible && icon.animate
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * Math.round(fall.period / fall.count) }
                    ParallelAnimation {
                        NumberAnimation {
                            target: parent; property: "y"
                            from: icon.size * 0.6; to: icon.size * 0.6 + fall.travel
                            duration: fall.period
                            easing.type: fall.flake ? Easing.InOutSine : Easing.InQuad
                        }
                        SequentialAnimation {
                            NumberAnimation {
                                target: parent; property: "opacity"
                                from: 0; to: 1
                                duration: Math.round(fall.period * 0.25)
                            }
                            NumberAnimation {
                                target: parent; property: "opacity"
                                to: 0
                                duration: Math.round(fall.period * 0.75)
                            }
                        }
                    }
                }
            }
        }
    }

    Fall {
        visible: icon.kind === "rain" || icon.kind === "drizzle"
        count: icon.kind === "drizzle" ? 2 : 3
        dropHeight: icon.size * (icon.kind === "drizzle" ? 0.1 : 0.17)
    }

    Fall {
        visible: icon.kind === "snow"
        flake: true
        count: 3
    }

    // ---- Lightning: a bolt that flashes on a loop. ----
    Shape {
        id: bolt
        visible: icon.kind === "thunder"
        width: icon.size * 0.3
        height: icon.size * 0.34
        x: icon.size * 0.36
        y: icon.size * 0.56
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: icon.warm
            strokeWidth: -1
            startX: bolt.width * 0.62; startY: 0
            PathLine { x: bolt.width * 0.16; y: bolt.height * 0.56 }
            PathLine { x: bolt.width * 0.48; y: bolt.height * 0.56 }
            PathLine { x: bolt.width * 0.3;  y: bolt.height }
            PathLine { x: bolt.width * 0.92; y: bolt.height * 0.4 }
            PathLine { x: bolt.width * 0.56; y: bolt.height * 0.4 }
            PathLine { x: bolt.width * 0.62; y: 0 }
        }

        SequentialAnimation on opacity {
            running: bolt.visible && icon.animate
            loops: Animation.Infinite
            NumberAnimation { to: 1.0; duration: 90 }
            NumberAnimation { to: 0.25; duration: 140 }
            NumberAnimation { to: 1.0; duration: 90 }
            NumberAnimation { to: 0.3; duration: 300 }
            PauseAnimation { duration: 1600 }
        }
    }

    // ---- Fog: bars sliding past each other. ----
    Item {
        visible: icon.kind === "fog"
        anchors.fill: parent

        Repeater {
            model: 4
            Rectangle {
                required property int index
                height: icon.size * 0.085
                radius: height / 2
                color: icon.cool
                opacity: 0.85
                width: icon.size * (index % 2 === 0 ? 0.72 : 0.56)
                x: icon.size * 0.14
                y: icon.size * (0.2 + index * 0.17)

                SequentialAnimation on x {
                    running: icon.animate
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 260 }
                    NumberAnimation {
                        to: icon.size * 0.24; duration: 1900
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: icon.size * 0.14; duration: 1900
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }
    }
}
