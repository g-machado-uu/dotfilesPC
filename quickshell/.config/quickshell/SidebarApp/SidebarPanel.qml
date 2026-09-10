import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import qs.CustomTheme

// The ML4W control panel that drops out of the status bar. This is only the
// content: the card, its border and the drop animation come from the BarPanel
// that hosts it.
//
// It used to be a full-height window pinned to the right screen edge; it is now
// a bounded card, so the scrollable section carries everything that does not
// fit rather than the panel growing to the height of the display.
Item {
    id: root

    // Natural width of the card. The height is set by the bar, which is the
    // only thing that knows how much room is left under it.
    readonly property real panelWidth: 420

    // Mirrors the hosting panel's state. Read-only from in here: the refresh
    // Processes below use it to re-poll on open, and anything that wants to
    // dismiss the panel calls close() instead of writing to it.
    property bool isOpen: false
    signal closeRequested()
    function close(): void { root.closeRequested() }

    property bool isHyprlandSettingsInstalled: false

    Process {
        command: ["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-command-exists hyprmod"]
        running: root.isOpen

        stdout: StdioCollector {
            onStreamFinished: {
                root.isHyprlandSettingsInstalled = (this.text.trim() === "0")
            }
        }
    }

    // --- REUSABLE COMPONENTS ---
    component ML4WMenuItem: MenuItem {
        id: control
        contentItem: Text {
            text: control.text
            font.family: Theme.fontFamily
            font.pixelSize: 14
            color: control.highlighted ? Theme.background : Theme.primary
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            implicitWidth: 200
            implicitHeight: 36
            color: control.highlighted ? Theme.primary : "transparent"
            radius: 4
        }
    }

    component ML4WButton: Button {
        Layout.fillWidth: true
        background: Rectangle {
            color: "transparent"
            border.color: Theme.primary
            border.width: 1
            radius: 10
        }
        contentItem: Text {
            text: parent.text
            font.family: Theme.fontFamily
            font.pixelSize: 16
            color: Theme.primary
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            padding: 8
        }
    }

    component ML4WSwitch: Switch {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 48
        implicitHeight: 26
        indicator: Rectangle {
            implicitWidth: 48
            implicitHeight: 26
            radius: 13
            color: parent.checked ? Theme.primary : Theme.background
            border.color: Theme.primary
            border.width: 1
            Rectangle {
                x: parent.parent.checked ? parent.width - width - 2 : 2
                y: 2
                implicitWidth: 22
                implicitHeight: 22
                radius: 11
                color: parent.parent.checked ? Theme.background : Theme.on_primary
                Behavior on x { NumberAnimation { duration: 150 } }
            }
        }
    }

    component SettingsWheel: Button {
        implicitWidth: 28
        implicitHeight: 28
        background: Rectangle { color: "transparent" }
        contentItem: Item {
            Image {
                anchors.centerIn: parent
                source: "../shared/icons/settings.svg"
                width: 18
                height: 18
                sourceSize.width: 18
                sourceSize.height: 18
                fillMode: Image.PreserveAspectFit
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: Theme.primary
                }
            }
        }
    }

    // Supports text glyphs (iconTxt) for MPRIS controls and SVG files (iconSrc) for sidebar icons
    component ActionIcon: Button {
        property string iconTxt: ""
        property string iconSrc: ""
        implicitWidth: 28
        implicitHeight: 28
        background: Rectangle { color: "transparent" }
        contentItem: Item {
            Text {
                anchors.centerIn: parent
                text: iconTxt
                visible: iconSrc === ""
                color: Theme.primary
                font.family: "monospace"
                font.pixelSize: 18
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
            }
            Image {
                anchors.centerIn: parent
                source: iconSrc
                width: 18
                height: 18
                sourceSize.width: 18
                sourceSize.height: 18
                visible: iconSrc !== ""
                fillMode: Image.PreserveAspectFit
                layer.enabled: iconSrc !== ""
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: Theme.primary
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        // --- TOP BAR (Light/Dark, Screenshot & Color Picker) ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ActionIcon {
                iconSrc: "../shared/icons/darklight.svg"
                onClicked: {
                    Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-toggle-theme"])
                }
            }

            ActionIcon {
                iconSrc: "../shared/icons/picker.svg"
                onClicked: {
                    root.close()
                    Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/settings/hyprpicker.sh"])
                }
            }

            ActionIcon {
                iconSrc: "../shared/icons/screenshot.svg"
                onClicked: {
                    root.close()
                    Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh"])
                }
            }

            Item { Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.primary; opacity: 0.3 }

        // --- THREE BUTTONS ROW ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ML4WButton {
                text: "Settings"
                onClicked: {
                    root.close()
                    Quickshell.execDetached(["qs", "ipc", "call", "settings", "open"])
                }
            }
            ML4WButton {
                text: "HyprMod"
                visible: root.isHyprlandSettingsInstalled
                onClicked: {
                    root.close()
                    Quickshell.execDetached(["hyprmod"])
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.primary; opacity: 0.3 }

        // --- SCROLLABLE CONTENT ---
        ScrollView {
            id: scrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: mainContentColumn.implicitHeight // Tells ScrollView how tall the inner content truly is
            clip: true

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                interactive: true
                contentItem: Rectangle {
                    implicitWidth: 6; radius: 3; color: Theme.primary
                    opacity: parent.pressed ? 1.0 : (parent.active ? 0.8 : 0.4)
                }
            }

            ColumnLayout {
                id: mainContentColumn
                width: scrollView.width
                spacing: 20

                // --- SLIDERS (Loudness & Brightness) ---
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 20

                    // LOUDNESS SLIDER
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 15

                        Image {
                            source: "../shared/icons/volume.svg"
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            sourceSize.width: 20
                            sourceSize.height: 20
                            fillMode: Image.PreserveAspectFit
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.primary
                            }
                        }

                        Slider {
                            id: volumeSlider
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            value: 50 // Default

                            Process {
                                command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'"]
                                running: root.isOpen
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        let val = parseInt(this.text.trim())
                                        if (!isNaN(val)) volumeSlider.value = val;
                                    }
                                }
                            }

                            onMoved: {
                                Quickshell.execDetached(["bash", "-c", "wpctl set-volume @DEFAULT_AUDIO_SINK@ " + Math.round(value) + "%"])
                            }

                            background: Rectangle {
                                x: volumeSlider.leftPadding
                                y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                implicitWidth: 200
                                implicitHeight: 6
                                width: volumeSlider.availableWidth
                                height: implicitHeight
                                radius: 3
                                color: Theme.background
                                border.color: Theme.primary
                                border.width: 1

                                Rectangle {
                                    width: volumeSlider.visualPosition * parent.width
                                    height: parent.height
                                    color: Theme.primary
                                    radius: 3
                                }
                            }

                            handle: Rectangle {
                                x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                                y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                implicitWidth: 16
                                implicitHeight: 16
                                radius: 8
                                color: volumeSlider.pressed ? Theme.background : Theme.primary
                                border.color: Theme.primary
                                border.width: 1
                            }
                        }
                    }

                    // BRIGHTNESS SLIDER
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 15

                        Image {
                            source: "../shared/icons/brightness.svg"
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            sourceSize.width: 20
                            sourceSize.height: 20
                            fillMode: Image.PreserveAspectFit
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.primary
                            }
                        }

                        Slider {
                            id: brightnessSlider
                            Layout.fillWidth: true
                            from: 10 // Guaranteed Minimum 10%
                            to: 100
                            value: 100

                            Process {
                                command: ["bash", "-c", "brightnessctl -m | awk -F, '{gsub(\"%\",\"\",$4); print $4}'"]
                                running: root.isOpen
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        let val = parseInt(this.text.trim())
                                        if (!isNaN(val)) brightnessSlider.value = Math.max(10, val);
                                    }
                                }
                            }

                            onMoved: {
                                Quickshell.execDetached(["bash", "-c", "brightnessctl set " + Math.round(value) + "%"])
                            }

                            background: Rectangle {
                                x: brightnessSlider.leftPadding
                                y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                implicitWidth: 200
                                implicitHeight: 6
                                width: brightnessSlider.availableWidth
                                height: implicitHeight
                                radius: 3
                                color: Theme.background
                                border.color: Theme.primary
                                border.width: 1

                                Rectangle {
                                    width: brightnessSlider.visualPosition * parent.width
                                    height: parent.height
                                    color: Theme.primary
                                    radius: 3
                                }
                            }

                            handle: Rectangle {
                                x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                                y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                implicitWidth: 16
                                implicitHeight: 16
                                radius: 8
                                color: brightnessSlider.pressed ? Theme.background : Theme.primary
                                border.color: Theme.primary
                                border.width: 1
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.primary; opacity: 0.3; Layout.topMargin: 5; Layout.bottomMargin: 5 }

                // --- MPRIS PLAYERS (Scrollable ListView) ---
                ListView {
                    id: mprisListView
                    Layout.fillWidth: true

                    // Dynamically scale based on players, up to 210px (max 2 players)
                    Layout.preferredHeight: contentHeight
                    Layout.maximumHeight: 210

                    spacing: 10
                    clip: true

                    model: Mpris.players.values
                    visible: Mpris.players.values.length > 0

                    // Force disable scrolling entirely unless there are 3+ players
                    interactive: mprisListView.count > 2

                    ScrollBar.vertical: ScrollBar {
                        // Explicitly hide the scrollbar unless there are 3+ players
                        policy: mprisListView.count > 2 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        interactive: true
                        contentItem: Rectangle {
                            implicitWidth: 6; radius: 3; color: Theme.primary
                            opacity: parent.pressed ? 1.0 : (parent.active ? 0.8 : 0.4)
                        }
                    }

                    delegate: Rectangle {
                        id: playerCard
                        property var player: modelData

                        width: mprisListView.width - 16
                        implicitHeight: 100

                        radius: 10
                        color: Theme.background
                        border.color: Theme.primary
                        border.width: 1
                        clip: true

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 15

                            // Cover Art Block
                            Rectangle {
                                implicitWidth: 80
                                implicitHeight: 80
                                radius: 8
                                color: "transparent"
                                border.color: Theme.primary
                                border.width: 1
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: player.trackArtUrl ? player.trackArtUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: player.trackArtUrl !== ""
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰝚" // Music note icon (fallback)
                                    font.family: "monospace"
                                    font.pixelSize: 32
                                    color: Theme.primary
                                    visible: !player.trackArtUrl || player.trackArtUrl === ""
                                }
                            }

                            // Track Info & Controls
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 5

                                Text {
                                    Layout.fillWidth: true
                                    text: player.trackTitle ? player.trackTitle : (player.identity ? player.identity : "No Media Playing")
                                    color: Theme.primary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        if (player.trackArtist) return player.trackArtist;
                                        if (player.trackArtists && player.trackArtists.length > 0) return player.trackArtists[0];
                                        return "Unknown Artist";
                                    }
                                    color: Theme.on_background
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    opacity: 0.8
                                }

                                Item { Layout.fillHeight: true }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 15

                                    Item { Layout.fillWidth: true }

                                    ActionIcon {
                                        iconTxt: "󰒮"
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        onClicked: player.previous()
                                    }

                                    ActionIcon {
                                        iconTxt: player.isPlaying ? "󰏤" : "󰐊"
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        onClicked: player.isPlaying = !player.isPlaying
                                    }

                                    ActionIcon {
                                        iconTxt: "󰒭"
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        onClicked: player.next()
                                    }

                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true;
                    implicitHeight: 1;
                    color: Theme.primary;
                    opacity: 0.3;
                    Layout.topMargin: 5;
                    Layout.bottomMargin: 5;
                    visible: Mpris.players.values.length > 0
                }

                // --- STATUS BAR ---
                // Shows or hides the Quickshell bar ("enabled" in statusbar.json).
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Status Bar"; color: Theme.primary; font.family: Theme.fontFamily; font.pixelSize: 16 }
                    Item { Layout.fillWidth: true }
                    ML4WSwitch {
                        id: statusbarSwitch
                        property bool ready: false
                        // Read the "enabled" flag from the master file: the
                        // ml4w-statusbar override when it exists, otherwise the
                        // shipped statusbar.json.
                        Process {
                            id: statusbarStateProc
                            command: ["bash", "-c", "f=~/.config/ml4w-statusbar/statusbar.json; [ -f \"$f\" ] || f=~/.config/ml4w/settings/statusbar.json; grep -q '\"enabled\"[[:space:]]*:[[:space:]]*false' \"$f\" && echo 0 || echo 1"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    statusbarSwitch.checked = (this.text.trim() === "1")
                                    statusbarSwitch.ready = true
                                }
                            }
                        }
                        // Re-read the state periodically while the sidebar is
                        // open so the switch tracks external toggles (e.g. the
                        // SUPER+CTRL+B keybinding) live, not just on reopen.
                        // triggeredOnStart gives the initial read on open.
                        Timer {
                            interval: 1000
                            repeat: true
                            running: root.isOpen
                            triggeredOnStart: true
                            onTriggered: statusbarStateProc.running = true
                        }
                        onClicked: {
                            if (!ready) return;
                            // Send an absolute command matching the switch's
                            // post-click position (rather than a blind toggle)
                            // so the switch always reflects the real bar state,
                            // even if the bar was toggled elsewhere meanwhile.
                            let cmd = checked ? "qs ipc call statusbar enable"
                                              : "qs ipc call statusbar disable"
                            console.log("Status Bar cmd: " + cmd)
                            Quickshell.execDetached(["bash", "-c", cmd])
                        }
                    }

                    SettingsWheel {
                        onClicked: statusbarMenu.open()
                        Menu {
                            id: statusbarMenu
                            y: parent.height
                            implicitWidth: 220
                            padding: 8

                            // Only offer "Edit Settings" once the user has an
                            // ml4w-statusbar override file to edit; the shipped
                            // statusbar.json is not meant to be edited directly.
                            property bool overrideExists: false
                            Process {
                                command: ["bash", "-c", "[ -f ~/.config/ml4w-statusbar/statusbar.json ] && echo 1 || echo 0"]
                                running: root.isOpen
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        statusbarMenu.overrideExists = (this.text.trim() === "1")
                                    }
                                }
                            }

                            background: Rectangle { color: Theme.background; border.color: Theme.primary; border.width: 1; radius: 8 }
                            ML4WMenuItem { text: "Reload Status Bar"; onClicked: {
                                    // Reads the settings file and reloads the
                                    // matching bar.
                                    Quickshell.execDetached(["bash", "-c", "~/.config/ml4w/scripts/ml4w-reload-statusbar"])
                                }
                            }
                            ML4WMenuItem {
                                text: "Edit Settings"
                                visible: statusbarMenu.overrideExists
                                height: visible ? implicitHeight : 0
                                onClicked: {
                                    root.close()
                                    // Edit the master file: the ml4w-statusbar override when it
                                    // exists, otherwise the shipped statusbar.json.
                                    Quickshell.execDetached(["bash", "-c", "f=~/.config/ml4w-statusbar/statusbar.json; [ -f \"$f\" ] || f=~/.config/ml4w/settings/statusbar.json; ~/.config/ml4w/settings/editor.sh \"$f\""])
                                }
                            }
                        }
                    }
                }

                // --- STATUSBAR ALWAYS EXPANDED (Quickshell) ---
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Statusbar Expanded"; color: Theme.primary; font.family: Theme.fontFamily; font.pixelSize: 16 }
                    Item { Layout.fillWidth: true }
                    ML4WSwitch {
                        id: statusbarExpandedSwitch
                        property bool ready: false
                        // Read the current state from the "alwaysExpanded" flag
                        // in the master file: the ml4w-statusbar override when it
                        // exists, otherwise the shipped statusbar.json. A missing
                        // file or flag counts as off.
                        Process {
                            command: ["bash", "-c", "f=~/.config/ml4w-statusbar/statusbar.json; [ -f \"$f\" ] || f=~/.config/ml4w/settings/statusbar.json; grep -q '\"alwaysExpanded\"[[:space:]]*:[[:space:]]*true' \"$f\" && echo 1 || echo 0"]
                            running: root.isOpen
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    console.log("Test for Statusbar Expanded: " + this.text.trim())
                                    statusbarExpandedSwitch.checked = (this.text.trim() === "1")
                                    statusbarExpandedSwitch.ready = true
                                }
                            }
                        }
                        onClicked: {
                            if (!ready) return;
                            // The statusbar owns the file write; just tell it
                            // the new state via IPC. `checked` already
                            // reflects the post-click position.
                            let ipcCmd = checked
                            ? "qs ipc call statusbar alwaysExpand"
                            : "qs ipc call statusbar autoCollapse"
                            console.log("Statusbar Expanded cmd: " + ipcCmd)
                            Quickshell.execDetached(["bash", "-c", ipcCmd])
                        }
                    }
                    Item { implicitWidth: 28 }
                }

                // --- GAMEMODE ---
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Gamemode"; color: Theme.primary; font.family: Theme.fontFamily; font.pixelSize: 16 }
                    Item { Layout.fillWidth: true }
                    ML4WSwitch {
                        id: gamemodeSwitch
                        property bool ready: false
                        Process {
                            command: ["bash", "-c", "test -f ~/.config/ml4w/settings/gamemode-enabled && echo 0 || echo 1"]
                            running: root.isOpen
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    console.log("Test for Gamemode: " + this.text.trim())
                                    gamemodeSwitch.checked = (this.text.trim() === "0")
                                    gamemodeSwitch.ready = true
                                }
                            }
                        }
                        onClicked: {
                            if (!ready) return;
                            Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/hypr/scripts/gamemode.sh"])
                        }
                    }
                    Item { implicitWidth: 28 }
                }

                // --- FASTFETCH ---
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Fastfetch"; color: Theme.primary; font.family: Theme.fontFamily; font.pixelSize: 16 }
                    Item { Layout.fillWidth: true }
                    ML4WSwitch {
                        id: fastfetchSwitch
                        property bool ready: false
                        Process {
                            command: ["bash", "-c", "test -f ~/.config/ml4w/settings/hide-fastfetch && echo 1 || echo 0"]
                            running: root.isOpen
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    console.log("Test for Fastfetch: " + this.text.trim())
                                    fastfetchSwitch.checked = (this.text.trim() === "0")
                                    fastfetchSwitch.ready = true
                                }
                            }
                        }
                        onClicked: {
                            if (!ready) return;
                            Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-toggle-fastfetch"])
                        }
                    }
                    Item { implicitWidth: 28 }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.primary; opacity: 0.3; Layout.topMargin: 5; Layout.bottomMargin: 5 }

                // --- WALLPAPER ---
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Wallpaper"; color: Theme.primary; font.family: Theme.fontFamily; font.pixelSize: 16 }
                    Item { Layout.fillWidth: true }
                    ActionIcon {
                        iconSrc: "../shared/icons/wallpaper.svg"
                        onClicked: {
                            root.close()
                            Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-wallpaper-app"])
                        }
                    }
                }

                // --- THEME ---
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Theme"; color: Theme.primary; font.family: Theme.fontFamily; font.pixelSize: 16 }
                    Item { Layout.fillWidth: true }
                    ActionIcon {
                        iconSrc: "../shared/icons/theme.svg"
                        onClicked: {
                            root.close()
                            Quickshell.execDetached(["qs", "ipc", "call", "settings", "open"])
                        }
                    }
                    SettingsWheel {
                        onClicked: themeMenu.open()
                        Menu {
                            id: themeMenu
                            y: parent.height

                            implicitWidth: 220
                            padding: 8

                            background: Rectangle { color: Theme.background; border.color: Theme.primary; border.width: 1; radius: 8 }
                            ML4WMenuItem { text: "Set GTK Theme"; onClicked: {
                                    root.close()
                                    Quickshell.execDetached(["nwg-look"])
                                }
                            }
                            ML4WMenuItem { text: "Set QT Theme"; onClicked: {
                                    root.close()
                                    Quickshell.execDetached(["qt6ct"])
                                }
                            }
                            ML4WMenuItem { text: "Refresh GTK Theme"; onClicked: {
                                    root.close()
                                    Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/hypr/scripts/gtk.sh"])
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
