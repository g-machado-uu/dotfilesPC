import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import qs.CustomTheme
import qs.shared
import qs.DesktopWidget

// The control centre that drops out of the sliders icon in the status bar
// (SUPER + CTRL + S). It also took over the old sidebar.
//
// Top to bottom, from what is changed most to what is only glanced at:
// shortcuts to the other panels, quick toggles, the notification count, the
// output and input levels, the way into the Appearance page, the weather, and
// whatever is playing last. Media keeps a fixed slot at the bottom, so a
// player appearing or disappearing never moves anything above it.
//
// This is only the content — the silhouette, translucency and drop animation
// come from the BarPanel that hosts it.
Item {
    id: root

    readonly property real panelWidth: 420
    readonly property real panelHeight: 714

    // Mirrors the hosting panel's state. Polling and animations only run while
    // the panel is actually on screen.
    property bool isOpen: false
    signal closeRequested()

    // Place name to look up, e.g. "Belfast, UK". Set from the bar's settings.
    property string location: "Belfast, UK"
    // Whether the desktop time/weather widget is on. Set from the bar.
    property bool weatherWidgetEnabled: true

    // ------------------------------------------------------------------
    // TOGGLE STATE
    // ------------------------------------------------------------------
    // Read by polling rather than through a service API, so the module keeps
    // working on any machine with NetworkManager, bluez and swaync installed
    // and needs no Quickshell version newer than the bar itself.
    property bool wifiOn: false
    property bool bluetoothOn: false
    property bool dndOn: false
    property bool caffeineOn: false
    property bool nightLightOn: false
    property bool gamemodeOn: false
    property int notificationCount: 0

    // "" is the main page; "wifi", "bluetooth" and "appearance" replace it.
    property string page: ""

    readonly property string home: Quickshell.env("HOME")

    Process {
        id: stateProc
        command: ["bash", "-c",
            "w=$(nmcli radio wifi 2>/dev/null); " +
            "b=$(bluetoothctl show 2>/dev/null | grep -c 'Powered: yes'); " +
            "d=$(swaync-client -D 2>/dev/null); " +
            "c=$(pgrep -x hypridle >/dev/null && echo 1 || echo 0); " +
            "n=$(pgrep -x hyprsunset >/dev/null && echo 1 || echo 0); " +
            "g=$([ -f \"$HOME/.config/ml4w/settings/gamemode-enabled\" ] && echo 1 || echo 0); " +
            "echo \"${w:-disabled}|${b:-0}|${d:-false}|$c|$n|$g\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = this.text.trim().split("|")
                if (parts.length < 6)
                    return
                root.wifiOn = parts[0].trim() === "enabled"
                root.bluetoothOn = parseInt(parts[1]) > 0
                root.dndOn = parts[2].trim() === "true"
                // hypridle running means the screen still blanks and locks, so
                // caffeine is the inverse of it.
                root.caffeineOn = parts[3].trim() !== "1"
                root.nightLightOn = parts[4].trim() === "1"
                // gamemode.sh drops this flag file while gamemode is on.
                root.gamemodeOn = parts[5].trim() === "1"
            }
        }
    }

    // Output and input levels, as percentages. wpctl talks to PipeWire, which
    // is what ML4W's audio stack runs on.
    property int volumeLevel: 0
    property int micLevel: 0
    property int brightnessLevel: 100

    Process {
        id: audioProc
        command: ["bash", "-c",
            "v=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2*100)}'); " +
            "m=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | awk '{print int($2*100)}'); " +
            "b=$(brightnessctl -m 2>/dev/null | awk -F, '{gsub(\"%\",\"\",$4); print $4}'); " +
            "echo \"${v:-0}|${m:-0}|${b:-100}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = this.text.trim().split("|")
                if (parts.length < 2)
                    return
                // Never yank a slider out from under the user mid-drag.
                if (!volumeSlider.pressed)
                    root.volumeLevel = parseInt(parts[0]) || 0
                if (!micSlider.pressed)
                    root.micLevel = parseInt(parts[1]) || 0
                if (parts.length > 2 && !brightnessSlider.pressed)
                    root.brightnessLevel = parseInt(parts[2]) || 0
            }
        }
    }

    function pollAudio(): void {
        audioProc.running = false
        audioProc.running = true
    }

    function pollState(): void {
        stateProc.running = false
        stateProc.running = true
    }

    // Re-read shortly after a toggle: nmcli and bluetoothctl return before the
    // radio has actually settled.
    Timer {
        id: settleTimer
        interval: 700
        onTriggered: root.pollState()
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.isOpen
        onTriggered: {
            root.pollState()
            root.pollAudio()
        }
    }

    // Live notification count, from the same waybar subscription the bar's
    // bell uses. It emits a JSON line on every add and close.
    Process {
        command: ["swaync-client", "-swb"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    let obj = JSON.parse(data)
                    root.notificationCount = parseInt(obj.text) || 0
                    if (obj.alt !== undefined)
                        root.dndOn = String(obj.alt).indexOf("dnd") >= 0
                } catch (e) {
                    // Ignore malformed lines.
                }
            }
        }
    }

    function run(cmd: string): void {
        Quickshell.execDetached(["bash", "-c", cmd])
        settleTimer.restart()
    }

    onIsOpenChanged: {
        if (root.isOpen) {
            // The weather catches up by itself: `active` follows isOpen.
            root.pollState()
            root.pollAudio()
        } else {
            // Always reopen on the main page, never mid-edit, and back on the
            // player that is actually playing.
            root.page = ""
            placeRow.editing = false
            root.playerPick = -1
        }
    }

    // ------------------------------------------------------------------
    // MEDIA
    // ------------------------------------------------------------------
    // Same choice as the bar's media module: the player that is playing,
    // otherwise the first one. With several players the counter on the card
    // pins another one until the panel closes.
    property int playerPick: -1

    readonly property var players: Mpris.players.values

    readonly property var player: {
        let list = root.players
        if (root.playerPick >= 0 && root.playerPick < list.length)
            return list[root.playerPick]
        for (let i = 0; i < list.length; i++) {
            if (list[i].isPlaying)
                return list[i]
        }
        return list.length > 0 ? list[0] : null
    }

    readonly property int playerIndex: root.player ? root.players.indexOf(root.player) : -1

    readonly property string artist: {
        if (!root.player)
            return ""
        if (root.player.trackArtist)
            return root.player.trackArtist
        if (root.player.trackArtists && root.player.trackArtists.length > 0)
            return root.player.trackArtists[0]
        return root.player.identity ? root.player.identity : ""
    }

    // Position only needs to tick while the card is actually on screen.
    Timer {
        interval: 1000
        repeat: true
        running: root.isOpen && root.page === "" && root.player !== null
                 && root.player.isPlaying
        onTriggered: mediaProgress.refresh()
    }

    // ------------------------------------------------------------------
    // WEATHER
    // ------------------------------------------------------------------
    // The same source the desktop widget uses (Open-Meteo), so the two always
    // show the same readings, in the same units. It re-geocodes by itself when
    // `location` changes and catches up whenever the panel opens.
    WeatherSource {
        id: weather
        location: root.location
        active: root.isOpen
    }

    // ------------------------------------------------------------------
    // LAYOUT
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

    // A quick-toggle tile: icon over label, filled when the thing is on. Every
    // tile is an on/off state; one-off actions live elsewhere as pills.
    component Tile: Rectangle {
        id: tile
        property string iconSrc: ""
        property string label: ""
        property bool on: false
        // When set, a chevron appears in the corner that opens this page;
        // clicking anywhere else still toggles the thing itself.
        property string page: ""
        signal activated()

        Layout.fillWidth: true
        implicitHeight: 58
        radius: 12
        color: tile.on ? Theme.primary
            : (tileMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g,
                                                 Theme.primary.b, 0.16) : "transparent")
        border.color: Theme.primary
        border.width: tile.on ? 0 : 1

        Behavior on color {
            ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            IconGlyph {
                Layout.alignment: Qt.AlignHCenter
                source: tile.iconSrc
                size: 19
                color: tile.on ? Theme.background : Theme.primary
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: tile.label
                color: tile.on ? Theme.background : Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }

        // Drawn over the MouseArea above so it takes the click first.
        Rectangle {
            visible: tile.page !== ""
            anchors.right: parent.right
            anchors.top: parent.top
            width: 24
            height: 24
            radius: 8
            color: chevronMouse.containsMouse
                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                : "transparent"

            IconGlyph {
                anchors.centerIn: parent
                source: "../shared/icons/chevron-right.svg"
                size: 13
                color: tile.on ? Theme.background : Theme.primary
                opacity: 0.75
            }

            MouseArea {
                id: chevronMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.page = tile.page
            }
        }
    }

    // A small round button that opens another panel, the same accent circle
    // the bar's own buttons fill on hover.
    component ShortcutButton: Rectangle {
        id: sc
        property string iconSrc: ""
        // Shown in the header while hovered, e.g. "Settings · Super+Shift+S".
        property string hint: ""
        // Same command as the matching Hyprland keybinding.
        property string command: ""
        readonly property bool hovered: scMouse.containsMouse

        implicitWidth: 28
        implicitHeight: 28
        radius: 14
        color: sc.hovered ? Theme.primary : "transparent"
        Behavior on color {
            ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
        }

        IconGlyph {
            anchors.centerIn: parent
            source: sc.iconSrc
            size: 15
            color: sc.hovered ? Theme.background : Theme.primary
        }

        MouseArea {
            id: scMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // The other panel replaces this one in the bar's single slot.
            onClicked: Quickshell.execDetached(["bash", "-c", sc.command])
        }
    }

    // The wind dart, drawn the way the desktop widget draws it: pointing along
    // the bearing the wind blows *from*, as a METAR reports it.
    component WindArrow: Shape {
        id: arrow
        property real bearing: 0
        property real glyphSize: 10

        implicitWidth: glyphSize
        implicitHeight: glyphSize
        preferredRendererType: Shape.GeometryRenderer

        transform: Rotation {
            origin.x: arrow.glyphSize / 2
            origin.y: arrow.glyphSize / 2
            angle: arrow.bearing
        }

        ShapePath {
            fillColor: Theme.primary
            strokeWidth: -1
            startX: arrow.glyphSize * 0.5; startY: 0
            PathLine { x: arrow.glyphSize * 0.95; y: arrow.glyphSize }
            PathLine { x: arrow.glyphSize * 0.5;  y: arrow.glyphSize * 0.7 }
            PathLine { x: arrow.glyphSize * 0.05; y: arrow.glyphSize }
            PathLine { x: arrow.glyphSize * 0.5;  y: 0 }
        }
    }

    // One reading in the weather details card: a small label over its value,
    // styled like the MIN / MAX pair beside the temperature.
    component WeatherStat: ColumnLayout {
        id: stat
        property string label: ""
        property string value: ""
        // Wind only: shows the dart before the label.
        property bool showArrow: false
        property real bearing: 0

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 1

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            WindArrow {
                Layout.alignment: Qt.AlignVCenter
                visible: stat.showArrow
                bearing: stat.bearing
                opacity: weather.loaded ? 0.8 : 0
            }
            Text {
                text: stat.label
                color: Theme.primary
                opacity: 0.6
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: stat.value
            color: Theme.on_background
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }
    }

    // A labelled level slider.
    component LevelSlider: RowLayout {
        id: lvl
        property string iconSrc: ""
        property int value: 0
        property int minimum: 0
        // Shell command template; %1 is replaced with the new percentage.
        property string setCommand: ""

        readonly property alias pressed: slider.pressed

        Layout.fillWidth: true
        spacing: 12

        IconGlyph {
            Layout.alignment: Qt.AlignVCenter
            source: lvl.iconSrc
            size: 18
            color: Theme.primary
        }

        Slider {
            id: slider
            Layout.fillWidth: true
            from: lvl.minimum
            to: 100
            value: lvl.value

            onMoved: {
                lvl.value = Math.round(value)
                Quickshell.execDetached(["bash", "-c",
                    lvl.setCommand.arg(Math.round(value))])
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

        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 34
            horizontalAlignment: Text.AlignRight
            text: lvl.value + "%"
            color: Theme.on_background
            font.family: Theme.fontFamily
            font.pixelSize: 12
            opacity: 0.8
        }
    }

    // ------------------------------------------------------------------
    // MAIN PAGE
    // ------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        visible: opacity > 0
        opacity: root.page === "" ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutQuint }
        }

        // --- SHORTCUTS ---
        // Only other panels live here; pages inside the control centre are
        // reached through chevrons instead, so the two never look alike.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: -4
            spacing: 4

            SectionLabel {
                readonly property string hint: wallpaperShortcut.hovered ? wallpaperShortcut.hint
                    : settingsShortcut.hovered ? settingsShortcut.hint
                    : ""
                Layout.fillWidth: true
                text: hint !== "" ? hint : "CONTROL CENTRE"
                opacity: hint !== "" ? 0.7 : 0.4
                elide: Text.ElideRight
            }

            ShortcutButton {
                id: wallpaperShortcut
                iconSrc: "../shared/icons/wallpaper.svg"
                hint: "WALLPAPERS · SUPER+CTRL+W"
                command: "$HOME/.config/ml4w/scripts/ml4w-wallpaper-app"
            }
            ShortcutButton {
                id: settingsShortcut
                iconSrc: "../shared/icons/settings.svg"
                hint: "SETTINGS · SUPER+SHIFT+S"
                command: "qs ipc call settings toggle"
            }
        }

        // --- QUICK TOGGLES ---
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 8
            rowSpacing: 8

            Tile {
                iconSrc: root.wifiOn ? "../shared/icons/wifi.svg"
                                     : "../shared/icons/wifi-off.svg"
                label: "Wi-Fi"
                on: root.wifiOn
                page: "wifi"
                onActivated: root.run("nmcli radio wifi " + (root.wifiOn ? "off" : "on"))
            }
            Tile {
                iconSrc: root.bluetoothOn ? "../shared/icons/bluetooth.svg"
                                          : "../shared/icons/bluetooth-off.svg"
                label: "Bluetooth"
                on: root.bluetoothOn
                page: "bluetooth"
                onActivated: root.run("bluetoothctl power " + (root.bluetoothOn ? "off" : "on"))
            }
            Tile {
                iconSrc: root.dndOn ? "../shared/icons/bell-off.svg"
                                    : "../shared/icons/bell.svg"
                label: "Do Not Disturb"
                on: root.dndOn
                onActivated: root.run("swaync-client -d")
            }
            Tile {
                iconSrc: "../shared/icons/caffeine.svg"
                label: "Caffeine"
                on: root.caffeineOn
                // ML4W's own script already toggles hypridle and reports back,
                // so screen locking keeps working the way the rest of the
                // desktop expects.
                onActivated: root.run(root.home + "/.config/hypr/scripts/hypridle.sh toggle")
            }
            Tile {
                iconSrc: "../shared/icons/moon.svg"
                label: "Night Light"
                on: root.nightLightOn
                // The same script SUPER + SHIFT + H runs.
                onActivated: root.run(root.home + "/.config/ml4w/scripts/ml4w-toggle-hyprsunset")
            }
            Tile {
                iconSrc: "../shared/icons/gamepad.svg"
                label: "Gamemode"
                on: root.gamemodeOn
                // The same script SUPER + ALT + G runs: animations and blur
                // off, wallpaper automation paused.
                onActivated: root.run(root.home + "/.config/hypr/scripts/gamemode.sh")
            }
        }

        // --- NOTIFICATIONS ---
        // Next to Do Not Disturb, which decides whether this count grows.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SectionLabel { text: "NOTIFICATIONS" }

            Rectangle {
                visible: root.notificationCount > 0
                implicitWidth: Math.max(20, countText.implicitWidth + 12)
                implicitHeight: 18
                radius: 9
                color: Theme.primary
                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: root.notificationCount
                    color: Theme.background
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }
            }

            Item { Layout.fillWidth: true }

            PillButton {
                text: "Clear all"
                enabled: root.notificationCount > 0
                onActivated: root.run("swaync-client -C")
            }

            // swaync owns the notification list and does not expose it over
            // D-Bus, so the list itself stays in its own panel; this opens it.
            PillButton {
                text: "Open"
                onActivated: {
                    Quickshell.execDetached(["swaync-client", "-t", "-sw"])
                    root.closeRequested()
                }
            }
        }

        // --- OUTPUT AND INPUT LEVELS ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            LevelSlider {
                id: volumeSlider
                iconSrc: root.volumeLevel > 0 ? "../shared/icons/volume.svg"
                                              : "../shared/icons/volume-muted.svg"
                value: root.volumeLevel
                setCommand: "wpctl set-volume @DEFAULT_AUDIO_SINK@ %1%"
                onValueChanged: root.volumeLevel = value
            }

            LevelSlider {
                id: micSlider
                iconSrc: root.micLevel > 0 ? "../shared/icons/mic.svg"
                                           : "../shared/icons/mic-off.svg"
                value: root.micLevel
                setCommand: "wpctl set-volume @DEFAULT_AUDIO_SOURCE@ %1%"
                onValueChanged: root.micLevel = value
            }

            LevelSlider {
                id: brightnessSlider
                iconSrc: "../shared/icons/brightness.svg"
                value: root.brightnessLevel
                // Never all the way to zero: a dark panel is hard to find again.
                minimum: 5
                setCommand: "brightnessctl set %1%"
                onValueChanged: root.brightnessLevel = value
            }
        }

        // --- APPEARANCE ---
        // A row, not a tile: it opens a page rather than switching something,
        // and it says what is behind it.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: 12
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b,
                           appearanceMouse.containsMouse ? 0.18 : 0.10)
            Behavior on color {
                ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 10

                IconGlyph {
                    Layout.alignment: Qt.AlignVCenter
                    source: "../shared/icons/theme.svg"
                    size: 17
                    color: Theme.primary
                }
                Text {
                    text: "Appearance"
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: "Dark style, GTK & Qt, weather widget"
                    color: Theme.on_background
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    opacity: 0.7
                    elide: Text.ElideRight
                }
                IconGlyph {
                    Layout.alignment: Qt.AlignVCenter
                    source: "../shared/icons/chevron-right.svg"
                    size: 14
                    color: Theme.primary
                    opacity: 0.75
                }
            }

            MouseArea {
                id: appearanceMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.page = "appearance"
            }
        }

        Divider {}

        // --- WEATHER ---
        // The place name doubles as its own setting: click it and type another
        // one. The status bar owns statusbar.json, so the new value is handed
        // to it over IPC and comes back here as a changed `location` binding,
        // which re-geocodes. The desktop widget follows the same binding.
        Item {
            id: placeRow
            Layout.fillWidth: true
            implicitHeight: 24
            property bool editing: false

            function beginEdit(): void {
                placeField.text = root.location
                placeRow.editing = true
                placeField.forceActiveFocus()
                placeField.selectAll()
            }

            function commit(): void {
                if (!placeRow.editing)
                    return
                placeRow.editing = false
                const v = placeField.text.trim()
                if (v === "" || v === root.location)
                    return
                Quickshell.execDetached(["qs", "ipc", "call", "statusbar",
                    "setWeatherLocation", v])
            }

            SectionLabel {
                id: placeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: !placeRow.editing
                text: (weather.place !== "" ? weather.place
                                            : root.location).toUpperCase()
                opacity: placeMouse.containsMouse ? 1 : 0.7
            }

            MouseArea {
                id: placeMouse
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: placeLabel.implicitWidth
                height: parent.height
                visible: !placeRow.editing
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: placeRow.beginEdit()
            }

            TextField {
                id: placeField
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 220
                implicitHeight: 24
                visible: placeRow.editing
                placeholderText: "Belfast, UK"
                color: Theme.primary
                placeholderTextColor: Qt.alpha(Theme.primary, 0.5)
                selectionColor: Theme.primary
                selectedTextColor: Theme.background
                font.family: Theme.fontFamily
                font.pixelSize: 12
                leftPadding: 8
                rightPadding: 8
                topPadding: 0
                bottomPadding: 0
                // Saved on Enter and when the field loses the keyboard.
                onEditingFinished: placeRow.commit()
                Keys.onEscapePressed: placeRow.editing = false
                background: Rectangle {
                    radius: 6
                    color: "transparent"
                    border.color: Theme.primary
                    border.width: placeField.activeFocus ? 2 : 1
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            WeatherIcon {
                Layout.alignment: Qt.AlignVCenter
                size: 54
                code: weather.code
                night: !weather.isDay
                animate: root.isOpen
                opacity: weather.loaded ? 1 : 0.35
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: weather.loaded ? weather.fmt(weather.temperature) : "--°"
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 30
                    font.bold: true
                }
                Text {
                    text: weather.error !== "" ? weather.error
                        : (weather.loaded ? weatherGlyph.label : "Loading…")
                    color: Theme.on_background
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    opacity: 0.8
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // Today's range, aligned to the right of the current reading.
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                RowLayout {
                    spacing: 6
                    Text {
                        text: "MIN"
                        color: Theme.primary; opacity: 0.6
                        font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true
                    }
                    Text {
                        text: weather.loaded ? weather.fmt(weather.todayMin) : "--°"
                        color: Theme.on_background
                        font.family: Theme.fontFamily; font.pixelSize: 13
                    }
                }
                RowLayout {
                    spacing: 6
                    Text {
                        text: "MAX"
                        color: Theme.primary; opacity: 0.6
                        font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true
                    }
                    Text {
                        text: weather.loaded ? weather.fmt(weather.todayMax) : "--°"
                        color: Theme.on_background
                        font.family: Theme.fontFamily; font.pixelSize: 13
                    }
                }
            }
        }

        // Condition text needs the same code→label mapping the glyph has, so it
        // borrows one from an off-screen instance rather than duplicating it.
        WeatherIcon {
            id: weatherGlyph
            visible: false
            animate: false
            code: weather.code
        }

        // --- DETAILS ---
        // The rest of the readings the desktop widget shows, in one card.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 46
            radius: 10
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 4

                WeatherStat {
                    label: "FEELS LIKE"
                    value: weather.loaded ? weather.fmt(weather.apparent) : "--°"
                }
                WeatherStat {
                    label: "HUMIDITY"
                    value: weather.loaded ? weather.humidity + "%" : "--%"
                }
                WeatherStat {
                    label: "WIND"
                    value: weather.loaded ? weather.windMetar : "--"
                    showArrow: true
                    bearing: weather.windDirection
                }
                WeatherStat {
                    label: "QNH"
                    value: weather.loaded ? Math.round(weather.pressure) + " hPa" : "--"
                }
            }
        }

        // --- NEXT THREE DAYS ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: weather.forecast

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 52
                    radius: 10
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        WeatherIcon {
                            Layout.alignment: Qt.AlignVCenter
                            size: 30
                            code: modelData.code
                            animate: root.isOpen
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: modelData.day
                                color: Theme.primary
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                text: weather.fmt(modelData.min) + " / " + weather.fmt(modelData.max)
                                color: Theme.on_background
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                opacity: 0.85
                            }
                        }
                    }
                }
            }

            // Keeps the row's height while the forecast is still loading.
            Item {
                visible: weather.forecast.length === 0
                Layout.fillWidth: true
                implicitHeight: 52
            }
        }

        // Any spare height goes here, so media stays pinned to the bottom.
        Item { Layout.fillHeight: true }

        Divider {}

        // --- MEDIA ---
        // Always the last item and always the same height: with nothing
        // playing it says so and dims its controls instead of collapsing.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 76
            radius: 12
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
            clip: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 12

                // Album art when the player offers it, a note glyph when not.
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 56
                    implicitHeight: 56
                    radius: 8
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
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: root.player
                                ? (root.player.trackTitle ? root.player.trackTitle : "Playing")
                                : "Nothing playing"
                            elide: Text.ElideRight
                            color: Theme.primary
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                        }

                        // Only with more than one player: which one this is,
                        // and a click moves to the next.
                        Rectangle {
                            visible: root.players.length > 1
                            implicitWidth: pickText.implicitWidth + 12
                            implicitHeight: 18
                            radius: 9
                            color: pickMouse.containsMouse ? Theme.primary : "transparent"
                            border.color: Theme.primary
                            border.width: 1
                            Text {
                                id: pickText
                                anchors.centerIn: parent
                                text: (root.playerIndex + 1) + "/" + root.players.length
                                color: pickMouse.containsMouse ? Theme.background : Theme.primary
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                            }
                            MouseArea {
                                id: pickMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.playerPick =
                                    (root.playerIndex + 1) % root.players.length
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.player ? root.artist : "Start something to control it here"
                        elide: Text.ElideRight
                        color: Theme.on_background
                        opacity: 0.8
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 8

                    TransportButton {
                        diameter: 28
                        iconSrc: "../shared/icons/skip-back.svg"
                        enabled: root.player !== null
                        onActivated: if (root.player) root.player.previous()
                    }
                    TransportButton {
                        diameter: 34
                        iconSrc: (root.player && root.player.isPlaying)
                            ? "../shared/icons/pause.svg" : "../shared/icons/play.svg"
                        enabled: root.player !== null
                        onActivated: if (root.player) root.player.isPlaying = !root.player.isPlaying
                    }
                    TransportButton {
                        diameter: 28
                        iconSrc: "../shared/icons/skip-forward.svg"
                        enabled: root.player !== null
                        onActivated: if (root.player) root.player.next()
                    }
                }
            }

            // Progress along the bottom edge. Players that do not report a
            // length simply show none.
            Item {
                id: mediaProgress
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.bottomMargin: 4
                height: 3
                visible: root.player !== null && root.player.length > 0

                property real fraction: 0
                function refresh(): void {
                    mediaProgress.fraction = (root.player && root.player.length > 0)
                        ? Math.min(1, root.player.position / root.player.length)
                        : 0
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 2
                    color: Theme.primary
                    opacity: 0.2
                }
                Rectangle {
                    width: parent.width * mediaProgress.fraction
                    height: parent.height
                    radius: 2
                    color: Theme.primary
                    Behavior on width {
                        NumberAnimation { duration: 400; easing.type: Easing.OutQuint }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // SUB-PAGES
    // ------------------------------------------------------------------
    // They take the main page's place rather than resizing the panel, so the
    // drop keeps its shape and the bar underneath never shifts.
    WifiPage {
        anchors.fill: parent
        anchors.margins: 16
        active: root.page === "wifi" && root.isOpen
        radioOn: root.wifiOn
        visible: opacity > 0
        opacity: root.page === "wifi" ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutQuint }
        }
        onBack: root.page = ""
        onToggleRadio: root.run("nmcli radio wifi " + (root.wifiOn ? "off" : "on"))
    }

    BluetoothPage {
        anchors.fill: parent
        anchors.margins: 16
        active: root.page === "bluetooth" && root.isOpen
        radioOn: root.bluetoothOn
        visible: opacity > 0
        opacity: root.page === "bluetooth" ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutQuint }
        }
        onBack: root.page = ""
        onToggleRadio: root.run("bluetoothctl power " + (root.bluetoothOn ? "off" : "on"))
    }

    AppearancePage {
        anchors.fill: parent
        anchors.margins: 16
        active: root.page === "appearance" && root.isOpen
        weatherWidgetOn: root.weatherWidgetEnabled
        visible: opacity > 0
        opacity: root.page === "appearance" ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutQuint }
        }
        onBack: root.page = ""
        onCloseRequested: root.closeRequested()
    }
}
