import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.shared
import qs.ControlCentreApp

// The sound panel: output and input levels, the device each one plays through,
// and a volume for every application that is playing sound. It drops out of the
// status bar when the speaker icon is clicked, in the bar or in the control
// centre, and replaces whatever panel was open.
//
// Everything comes from Quickshell's PipeWire service, so levels follow changes
// made anywhere else (keys, pavucontrol) as they happen, with no polling.
//
// This is only the content — the silhouette, translucency and drop animation
// come from the BarPanel that hosts it.
Item {
    id: root

    // Mirrors the hosting panel's state. Nodes are only tracked while it is on
    // screen.
    property bool isOpen: false
    signal closeRequested()

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    // Hardware devices only; application streams are listed separately.
    readonly property var sinks: Pipewire.nodes.values.filter(
        n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(
        n => n.audio && !n.isSink && !n.isStream)

    // The applications feeding the default output, one entry per stream.
    PwNodeLinkTracker {
        id: playback
        node: root.sink
    }

    readonly property var apps: {
        let out = []
        let seen = []
        const groups = playback.linkGroups
        for (let i = 0; i < groups.length; i++) {
            const n = groups[i].source
            if (!n || !n.isStream || seen.indexOf(n.id) >= 0)
                continue
            // speech-dispatcher keeps a silent stream open at all times.
            if (/^speech-dispatcher/.test(root.appName(n)))
                continue
            seen.push(n.id)
            out.push(n)
        }
        return out
    }

    // Volumes, mute states and stream properties are only live for tracked
    // nodes.
    PwObjectTracker {
        objects: root.isOpen
            ? [root.sink, root.source].concat(root.sinks, root.sources, root.apps)
                .filter(n => n !== null)
            : []
    }

    onIsOpenChanged: {
        if (!root.isOpen) {
            outputPicker.expanded = false
            inputPicker.expanded = false
        }
    }

    // ------------------------------------------------------------------
    // NAMES AND ICONS
    // ------------------------------------------------------------------
    function deviceName(n: var): string {
        if (!n)
            return "No device"
        return n.description || n.nickname || n.name || "Unknown device"
    }

    function appName(n: var): string {
        const p = n.properties || ({})
        return p["application.name"] || n.description || n.nickname || n.name
            || "Unknown"
    }

    // What the stream is playing, when it says: a browser tab's title, a
    // track. Left out when it only repeats the application's name.
    function mediaName(n: var): string {
        const p = n.properties || ({})
        const m = p["media.name"] || ""
        const generic = ["playback", "audio stream", "audiostream", "output"]
        return (m === root.appName(n) || generic.indexOf(m.toLowerCase()) >= 0)
            ? "" : m
    }

    // The stream's own icon name first, then an icon or desktop entry named
    // after its program. "" when nothing matched, which shows a note glyph.
    function appIcon(n: var): string {
        const p = n.properties || ({})
        const tries = [p["application.icon-name"], p["application.process.binary"],
                       p["application.id"], p["application.name"]]
        for (let i = 0; i < tries.length; i++) {
            const t = tries[i]
            if (!t)
                continue
            let hit = Quickshell.iconPath(t, true)
            if (hit === "")
                hit = Quickshell.iconPath(String(t).toLowerCase(), true)
            if (hit !== "")
                return hit
            const entry = DesktopEntries.heuristicLookup(t)
            if (entry && entry.icon) {
                hit = Quickshell.iconPath(entry.icon, true)
                if (hit !== "")
                    return hit
            }
        }
        return ""
    }

    // ------------------------------------------------------------------
    // COMPONENTS
    // ------------------------------------------------------------------
    component Divider: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.primary
        opacity: 0.22
    }

    component SectionLabel: Text {
        color: Theme.primary
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
        opacity: 0.7
    }

    // The control centre's slider, bound straight to a node's volume. Capped
    // at 100%, like the control centre and the bar.
    component VolumeSlider: Slider {
        id: slider
        property PwNode node: null
        // Not "live": Slider already has a (final) property of that name.
        readonly property bool hasAudio: slider.node !== null && slider.node.audio !== null
        readonly property bool muted: slider.hasAudio && slider.node.audio.muted

        from: 0
        to: 100
        value: slider.hasAudio ? Math.round(slider.node.audio.volume * 100) : 0
        enabled: slider.hasAudio
        opacity: slider.muted ? 0.45 : 1
        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutQuint }
        }

        // Moving the slider brings a muted stream back.
        onMoved: {
            if (!slider.hasAudio)
                return
            slider.node.audio.muted = false
            slider.node.audio.volume = Math.round(slider.value) / 100
        }

        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            implicitHeight: 6
            height: implicitHeight
            radius: 3
            color: Theme.background
            border.color: Theme.primary
            border.width: 1

            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: 3
                color: Theme.primary
            }
        }

        handle: Rectangle {
            x: slider.leftPadding
                + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            implicitWidth: 16
            implicitHeight: 16
            radius: 8
            color: slider.pressed ? Theme.background : Theme.primary
            border.color: Theme.primary
            border.width: 1
        }
    }

    component Percent: Text {
        property PwNode node: null
        readonly property bool live: node !== null && node.audio !== null
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 38
        horizontalAlignment: Text.AlignRight
        text: !live ? "--"
            : node.audio.muted ? "Muted"
            : Math.round(node.audio.volume * 100) + "%"
        color: Theme.on_background
        font.family: Theme.fontFamily
        font.pixelSize: 12
        opacity: 0.8
    }

    // A round icon button that mutes and unmutes, filled with the accent on
    // hover like the bar's own buttons.
    component MuteButton: Rectangle {
        id: btn
        property PwNode node: null
        property string iconSrc: ""
        property string mutedIconSrc: ""
        readonly property bool live: btn.node !== null && btn.node.audio !== null
        readonly property bool muted: btn.live && btn.node.audio.muted

        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        color: btnMouse.containsMouse ? Theme.primary : "transparent"
        Behavior on color {
            ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
        }

        IconGlyph {
            anchors.centerIn: parent
            source: btn.muted ? btn.mutedIconSrc : btn.iconSrc
            size: 18
            color: btnMouse.containsMouse ? Theme.background : Theme.primary
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: btn.live
            onClicked: btn.node.audio.muted = !btn.node.audio.muted
        }
    }

    // The device a direction plays through. Collapsed it is one row naming
    // the current device; clicked it lists the others to switch to.
    component DevicePicker: ColumnLayout {
        id: picker
        property var nodes: []
        property PwNode current: null
        property bool isOutput: true
        property bool expanded: false
        readonly property bool canPick: picker.nodes.length > 1

        Layout.fillWidth: true
        spacing: 4

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 34
            radius: 10
            color: Qt.alpha(Theme.primary,
                (picker.canPick && currentMouse.containsMouse) ? 0.18 : 0.10)
            Behavior on color {
                ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.deviceName(picker.current)
                    color: Theme.on_background
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                IconGlyph {
                    Layout.alignment: Qt.AlignVCenter
                    visible: picker.canPick
                    source: "../shared/icons/chevron-right.svg"
                    size: 14
                    color: Theme.primary
                    opacity: 0.75
                    rotation: picker.expanded ? 90 : 0
                    Behavior on rotation {
                        NumberAnimation { duration: 180; easing.type: Easing.OutQuint }
                    }
                }
            }

            MouseArea {
                id: currentMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: picker.canPick
                cursorShape: Qt.PointingHandCursor
                onClicked: picker.expanded = !picker.expanded
            }
        }

        Repeater {
            model: picker.expanded ? picker.nodes : []

            Rectangle {
                id: choice
                required property var modelData
                readonly property bool selected: picker.current !== null
                    && choice.modelData.id === picker.current.id

                Layout.fillWidth: true
                Layout.leftMargin: 8
                implicitHeight: 30
                radius: 8
                color: choice.selected ? Theme.primary
                    : (choiceMouse.containsMouse ? Qt.alpha(Theme.primary, 0.16)
                                                 : "transparent")
                Behavior on color {
                    ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: Text.AlignVCenter
                    text: root.deviceName(choice.modelData)
                    color: choice.selected ? Theme.background : Theme.on_background
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: choice.selected
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: choiceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (picker.isOutput)
                            Pipewire.preferredDefaultAudioSink = choice.modelData
                        else
                            Pipewire.preferredDefaultAudioSource = choice.modelData
                        picker.expanded = false
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // LAYOUT
    // ------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "Sound"
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.bold: true
            }

            // Everything this panel leaves out (profiles, ports, balance).
            PillButton {
                text: "Advanced"
                onActivated: {
                    Quickshell.execDetached(["pavucontrol"])
                    root.closeRequested()
                }
            }
        }

        // --- OUTPUT ---
        SectionLabel { text: "OUTPUT" }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MuteButton {
                node: root.sink
                iconSrc: "../shared/icons/volume.svg"
                mutedIconSrc: "../shared/icons/volume-muted.svg"
            }
            VolumeSlider {
                Layout.fillWidth: true
                node: root.sink
            }
            Percent { node: root.sink }
        }

        DevicePicker {
            id: outputPicker
            nodes: root.sinks
            current: root.sink
            isOutput: true
        }

        // --- INPUT ---
        SectionLabel {
            Layout.topMargin: 4
            text: "INPUT"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MuteButton {
                node: root.source
                iconSrc: "../shared/icons/mic.svg"
                mutedIconSrc: "../shared/icons/mic-off.svg"
            }
            VolumeSlider {
                Layout.fillWidth: true
                node: root.source
            }
            Percent { node: root.source }
        }

        DevicePicker {
            id: inputPicker
            nodes: root.sources
            current: root.source
            isOutput: false
        }

        Divider { Layout.topMargin: 4 }

        // --- APPLICATIONS ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SectionLabel { text: "APPLICATIONS" }

            Rectangle {
                visible: root.apps.length > 0
                implicitWidth: Math.max(20, appCount.implicitWidth + 12)
                implicitHeight: 18
                radius: 9
                color: Theme.primary
                Text {
                    id: appCount
                    anchors.centerIn: parent
                    text: root.apps.length
                    color: Theme.background
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }
            }

            Item { Layout.fillWidth: true }
        }

        // Takes whatever height is left, and scrolls when many things play.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: root.apps.length === 0
                text: "Nothing is playing sound"
                color: Theme.on_background
                font.family: Theme.fontFamily
                font.pixelSize: 12
                opacity: 0.6
            }

            ListView {
                anchors.fill: parent
                clip: true
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                model: root.apps

                delegate: Rectangle {
                    id: app
                    required property var modelData
                    readonly property PwNode node: app.modelData
                    readonly property bool live: app.node !== null && app.node.audio !== null
                    readonly property bool muted: app.live && app.node.audio.muted
                    readonly property string icon: root.appIcon(app.node)
                    readonly property string media: root.mediaName(app.node)

                    width: ListView.view.width
                    implicitHeight: 64
                    radius: 12
                    color: Qt.alpha(Theme.primary, 0.10)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 12
                        spacing: 12

                        // The application's icon doubles as its mute button.
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 40
                            implicitHeight: 40
                            radius: 10
                            color: iconMouse.containsMouse
                                ? Qt.alpha(Theme.primary, 0.22) : "transparent"
                            Behavior on color {
                                ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
                            }

                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: 28
                                visible: app.icon !== ""
                                source: app.icon
                                opacity: app.muted ? 0.35 : 1
                                Behavior on opacity {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutQuint }
                                }
                            }

                            IconGlyph {
                                anchors.centerIn: parent
                                visible: app.icon === ""
                                source: "../shared/icons/music.svg"
                                size: 22
                                color: Theme.primary
                                opacity: app.muted ? 0.35 : 1
                            }

                            // Muted badge in the corner.
                            Rectangle {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                width: 18
                                height: 18
                                radius: 9
                                color: Theme.primary
                                visible: opacity > 0
                                opacity: app.muted ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutQuint }
                                }
                                IconGlyph {
                                    anchors.centerIn: parent
                                    source: "../shared/icons/volume-muted.svg"
                                    size: 11
                                    color: Theme.background
                                }
                            }

                            MouseArea {
                                id: iconMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: app.live
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.node.audio.muted = !app.node.audio.muted
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    Layout.fillWidth: true
                                    text: root.appName(app.node)
                                    color: Theme.primary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Percent { node: app.node }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: app.media !== ""
                                text: app.media
                                color: Theme.on_background
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                opacity: 0.7
                                elide: Text.ElideRight
                            }

                            VolumeSlider {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 20
                                node: app.node
                            }
                        }
                    }
                }
            }
        }
    }
}
