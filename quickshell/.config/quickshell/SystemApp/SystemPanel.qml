import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.shared
import qs.ControlCentreApp

// The system panel: a closer look than the SysMonitor bubbles, as a panel of
// the bar. GPU, CPU, memory, disks and network, each with a minute of history.
//
// Clicking the CPU card turns the whole panel into the per-core view; Back
// returns. Nothing is sampled while the panel is closed (see SystemStats).
//
// This is only the content: the silhouette, translucency and drop animation
// come from the BarPanel that hosts it.
Item {
    id: root

    property bool isOpen: false
    signal closeRequested()

    // "" is the overview, "cores" the per-core view.
    property string page: ""

    readonly property real panelWidth: 720
    // As tall as the overview needs; the per-core view fits in the same space.
    readonly property real panelHeight: overview.implicitHeight
        + overview.anchors.topMargin + overview.anchors.bottomMargin

    onIsOpenChanged: if (!root.isOpen) root.page = ""

    SystemStats {
        id: stats
        active: root.isOpen
    }

    // Series colours. The theme's own accents are often close shades of one
    // hue, so series that share a chart would be hard to tell apart; these
    // turn the primary's hue round the wheel instead, keeping its lightness
    // and saturation, so they still follow the wallpaper. Temperature uses
    // the theme's error red.
    function turn(k: real): color {
        return Qt.hsla((Theme.primary.hslHue + k + 1) % 1,
                       Math.max(0.45, Theme.primary.hslSaturation),
                       Math.min(0.72, Math.max(0.55, Theme.primary.hslLightness)), 1)
    }
    readonly property color c1: Theme.primary
    readonly property color c2: turn(0.33)
    readonly property color c3: turn(0.55)
    readonly property color c4: Theme.error
    readonly property var palette: [c1, turn(0.33), turn(0.55), turn(0.75)]

    function pct(v) { return Math.round(Math.max(0, Math.min(1, v)) * 100) }
    function scaled(list, k) { return list.map(v => v * k) }

    // Axis labels for rates, short enough for the label column.
    function axisRate(b) {
        if (b >= 1048576) return (b / 1048576).toFixed(b >= 10485760 ? 0 : 1) + " MiB/s"
        if (b >= 1024) return Math.round(b / 1024) + " KiB/s"
        return Math.round(b) + " B/s"
    }

    // ------------------------------------------------------------------
    // COMPONENTS
    // ------------------------------------------------------------------
    component Card: Rectangle {
        id: card
        property string title: ""
        property string subtitle: ""
        default property alias content: body.data

        radius: 12
        color: Qt.alpha(Theme.primary, 0.08)
        implicitHeight: body.implicitHeight + 24
        implicitWidth: body.implicitWidth + 24

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: card.title
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: card.subtitle === ""
                }
                Text {
                    visible: card.subtitle !== ""
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: card.subtitle
                    color: Theme.on_background
                    opacity: 0.6
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }
    }

    // A colour swatch, a name and the current value, under a chart.
    component Legend: RowLayout {
        property color swatch: Theme.primary
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 6
        Rectangle { implicitWidth: 10; implicitHeight: 10; radius: 3; color: parent.swatch }
        Text {
            Layout.fillWidth: true
            text: parent.label
            color: Theme.on_background
            opacity: 0.8
            font.family: Theme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
        }
        Text {
            text: parent.value
            color: Theme.on_background
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
        }
    }

    // A thin level bar.
    component Level: Rectangle {
        property real fraction: 0
        property color fill: Theme.primary
        Layout.fillWidth: true
        implicitHeight: 6
        radius: 3
        color: Qt.alpha(Theme.on_background, 0.12)
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.fraction))
            height: parent.height
            radius: 3
            color: parent.fill
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
        }
    }

    // A label over a level bar with its figure on the right, as in the disk
    // and memory cards.
    component LevelRow: ColumnLayout {
        property string label: ""
        property string value: ""
        property real fraction: 0
        property color fill: Theme.primary
        Layout.fillWidth: true
        spacing: 4
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: parent.parent.label
                color: Theme.on_background
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            Text {
                text: parent.parent.value
                color: Theme.on_background
                opacity: 0.85
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
        }
        Level { fraction: parent.fraction; fill: parent.fill }
    }

    // One core as a labelled horizontal bar.
    component CoreBar: RowLayout {
        property int core: 0
        property real load: 0
        Layout.fillWidth: true
        spacing: 8
        Text {
            Layout.preferredWidth: 46
            text: "Core " + parent.core
            color: Theme.on_background
            opacity: 0.75
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
        Level {
            fraction: parent.load
            fill: parent.load > 0.85 ? root.c4 : root.c1
        }
        Text {
            Layout.preferredWidth: 34
            horizontalAlignment: Text.AlignRight
            text: root.pct(parent.load) + "%"
            color: Theme.on_background
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
        }
    }

    // ------------------------------------------------------------------
    // OVERVIEW
    // ------------------------------------------------------------------
    ColumnLayout {
        id: overview
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        visible: opacity > 0
        opacity: root.page === "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuint } }

        Text {
            text: "System"
            color: Theme.primary
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.bold: true
        }

        // --- GPU | RAM + DISK USAGE ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Card {
                visible: stats.gpuKind !== ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: stats.gpuName !== "" ? stats.gpuName : "GPU"

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 6

                    // Usage, on both kinds of GPU.
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                        spacing: 4
                        HistoryChart {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            revision: stats.tick
                            format: v => Math.round(v) + "%"
                            series: [{ values: root.scaled(stats.gpuUtilHist, 100), color: root.c1 }]
                        }
                        Legend { swatch: root.c1; label: "Usage"; value: root.pct(stats.gpuUtil) + "%" }
                    }

                    // Temperature (NVIDIA) or clock (iGPU).
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                        spacing: 4
                        HistoryChart {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            revision: stats.tick
                            maximum: stats.gpuKind === "nvidia" ? 100 : Math.max(1, stats.gpuFreqMax)
                            format: stats.gpuKind === "nvidia" ? (v => Math.round(v) + " °C")
                                                               : (v => Math.round(v) + " MHz")
                            series: [{ values: stats.gpuKind === "nvidia" ? stats.gpuTempHist
                                                                          : stats.gpuFreqHist,
                                       color: root.c4 }]
                        }
                        Legend {
                            swatch: root.c4
                            label: stats.gpuKind === "nvidia" ? "Temperature" : "Clock"
                            value: stats.gpuKind === "nvidia" ? Math.round(stats.gpuTemp) + " °C"
                                                              : Math.round(stats.gpuFreq) + " MHz"
                        }
                    }

                    // Power and VRAM: NVIDIA only.
                    ColumnLayout {
                        visible: stats.gpuKind === "nvidia"
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                        spacing: 4
                        HistoryChart {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            revision: stats.tick
                            maximum: Math.max(1, stats.gpuPowerMax)
                            format: v => Math.round(v) + " W"
                            series: [{ values: stats.gpuPowerHist, color: root.c2 }]
                        }
                        Legend { swatch: root.c2; label: "Power"; value: Math.round(stats.gpuPower) + " W" }
                    }
                    ColumnLayout {
                        visible: stats.gpuKind === "nvidia"
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                        spacing: 4
                        HistoryChart {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            revision: stats.tick
                            maximum: Math.max(1, stats.vramTotal)
                            format: v => v.toFixed(v >= 10 ? 0 : 1) + " GiB"
                            series: [{ values: stats.vramHist, color: root.c3 }]
                        }
                        Legend { swatch: root.c3; label: "VRAM"; value: stats.gib(stats.vramUsed) + " GiB" }
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: 250
                Layout.fillWidth: stats.gpuKind === ""
                Layout.alignment: Qt.AlignTop
                spacing: 10

                Card {
                    Layout.fillWidth: true
                    title: "RAM"
                    subtitle: stats.gib(stats.memTotal) + " GiB"
                    LevelRow {
                        label: "Used"
                        value: stats.gib(stats.memUsed) + " GiB"
                        fraction: stats.memTotal > 0 ? stats.memUsed / stats.memTotal : 0
                    }
                    LevelRow {
                        visible: stats.swapTotal > 0
                        label: "Swap"
                        value: stats.gib(stats.swapUsed) + " / " + stats.gib(stats.swapTotal) + " GiB"
                        fraction: stats.swapTotal > 0 ? stats.swapUsed / stats.swapTotal : 0
                        fill: root.c2
                    }
                }

                Card {
                    Layout.fillWidth: true
                    title: "Disk usage"
                    subtitle: {
                        let t = 0
                        for (const f of stats.filesystems) t += f.size
                        return t > 0 ? stats.size(t) + " total" : ""
                    }
                    Repeater {
                        model: stats.filesystems
                        LevelRow {
                            required property var modelData
                            label: modelData.label
                            value: Math.round(100 * modelData.used / modelData.size) + "%  ·  "
                                   + stats.size(modelData.size)
                            fraction: modelData.used / modelData.size
                            fill: fraction > 0.9 ? root.c4 : root.c1
                        }
                    }
                }
            }
        }

        // --- CPU: the widest card, and the way into the per-core view ---
        Card {
            id: cpuCard
            Layout.fillWidth: true
            title: stats.cpuName !== "" ? stats.cpuName : "CPU"
            subtitle: stats.cores.length + " threads · click for every core"
            color: Qt.alpha(Theme.primary, cpuMouse.containsMouse ? 0.14 : 0.08)
            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutQuint } }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true; Layout.preferredWidth: 200
                    spacing: 4
                    HistoryChart {
                        Layout.fillWidth: true
                        implicitHeight: 100
                        revision: stats.tick
                        format: v => Math.round(v) + "%"
                        series: [{ values: root.scaled(stats.cpuHist, 100), color: root.c1 }]
                    }
                    Legend { swatch: root.c1; label: "Total usage"; value: root.pct(stats.cpuUsage) + "%" }
                }

                ColumnLayout {
                    Layout.fillWidth: true; Layout.preferredWidth: 200
                    spacing: 4
                    HistoryChart {
                        Layout.fillWidth: true
                        implicitHeight: 100
                        revision: stats.tick
                        format: v => Math.round(v) + " °C"
                        series: [{ values: stats.cpuTempHist, color: root.c4 }]
                    }
                    Legend { swatch: root.c4; label: "Temperature"; value: Math.round(stats.cpuTemp) + " °C" }
                }

                // The busiest cores right now.
                ColumnLayout {
                    // Fixed: the bars inside fill whatever they are given, and
                    // would otherwise take the charts' room.
                    Layout.preferredWidth: 190
                    Layout.maximumWidth: 190
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignTop
                    spacing: 6
                    Text {
                        text: "BUSIEST CORES"
                        color: Theme.primary
                        opacity: 0.7
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }
                    Repeater {
                        model: {
                            const idx = stats.cores.map((v, i) => i)
                            idx.sort((a, b) => stats.cores[b] - stats.cores[a])
                            return idx.slice(0, 5)
                        }
                        CoreBar {
                            required property int modelData
                            core: modelData
                            load: stats.cores[modelData] || 0
                        }
                    }
                }
            }

            MouseArea {
                id: cpuMouse
                parent: cpuCard
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.page = "cores"
            }
        }

        // --- DISK WRITES | NETWORK ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Card {
                visible: stats.drives.length > 0
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                title: "Disk writes"
                HistoryChart {
                    Layout.fillWidth: true
                    implicitHeight: 100
                    revision: stats.tick
                    autoScale: true
                    maximum: 1048576
                    format: v => root.axisRate(v)
                    series: stats.drives.map((d, i) => ({
                        values: stats.driveWriteHist[d.name] || [],
                        color: root.palette[i % root.palette.length] }))
                }
                Repeater {
                    model: stats.drives
                    Legend {
                        required property var modelData
                        required property int index
                        swatch: root.palette[index % root.palette.length]
                        label: modelData.label + (modelData.model !== "" ? "  ·  " + modelData.model : "")
                        value: stats.rate(stats.driveWrite[modelData.name] || 0)
                    }
                }
            }

            Card {
                visible: stats.netIface !== ""
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                title: "Network"
                subtitle: stats.netIface
                HistoryChart {
                    Layout.fillWidth: true
                    implicitHeight: 100
                    revision: stats.tick
                    autoScale: true
                    maximum: 1048576
                    format: v => root.axisRate(v)
                    series: [{ values: stats.netRxHist, color: root.c1 },
                             { values: stats.netTxHist, color: root.c2 }]
                }
                Legend { swatch: root.c1; label: "Download"; value: stats.rate(stats.netRx) }
                Legend { swatch: root.c2; label: "Upload"; value: stats.rate(stats.netTx) }
                Item { Layout.fillHeight: true }
            }
        }
    }

    // ------------------------------------------------------------------
    // PER-CORE VIEW
    // ------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        visible: opacity > 0
        opacity: root.page === "cores" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuint } }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: (stats.cpuName !== "" ? stats.cpuName : "CPU") + " · every core"
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.bold: true
                elide: Text.ElideRight
            }
            PillButton {
                text: "Back"
                onActivated: root.page = ""
            }
        }

        Card {
            Layout.fillWidth: true
            title: "Total usage"
            subtitle: root.pct(stats.cpuUsage) + "%  ·  " + Math.round(stats.cpuTemp) + " °C"
            HistoryChart {
                Layout.fillWidth: true
                implicitHeight: 110
                revision: stats.tick
                format: v => Math.round(v) + "%"
                series: [{ values: root.scaled(stats.cpuHist, 100), color: root.c1 }]
            }
        }

        // A small chart per core, like a task manager: two columns up to 8
        // threads, four up to 32, eight up to 64. Past that the charts would
        // be too small to read, so it falls back to plain bars.
        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "Cores"
            subtitle: stats.cores.length + " threads"

            readonly property int n: stats.cores.length
            readonly property int cols: n <= 8 ? 2 : (n <= 32 ? 4 : 8)

            GridLayout {
                visible: parent.parent.n <= 64
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: parent.parent.cols
                columnSpacing: 12
                rowSpacing: 10
                Repeater {
                    model: stats.cores.length <= 64 ? stats.cores.length : 0
                    ColumnLayout {
                        required property int index
                        readonly property real load: stats.cores[index] || 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 1
                        spacing: 3
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: "Core " + parent.parent.index
                                color: Theme.on_background
                                opacity: 0.75
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                            Text {
                                text: root.pct(parent.parent.load) + "%"
                                color: parent.parent.load > 0.85 ? root.c4 : Theme.on_background
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                        HistoryChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            implicitHeight: 30
                            showAxis: false
                            revision: stats.tick
                            series: [{ values: root.scaled(stats.coreHist[parent.index] || [], 100),
                                       color: parent.load > 0.85 ? root.c4 : root.c1 }]
                        }
                    }
                }
            }

            GridLayout {
                visible: parent.parent.n > 64
                Layout.fillWidth: true
                columns: 4
                columnSpacing: 18
                rowSpacing: 6
                Repeater {
                    model: stats.cores.length > 64 ? stats.cores.length : 0
                    CoreBar {
                        required property int index
                        Layout.preferredWidth: 1
                        core: index
                        load: stats.cores[index] || 0
                    }
                }
            }
        }
    }
}
