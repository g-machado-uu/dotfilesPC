import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.shared

// The notification centre that drops out of the bell in the status bar:
// quick toggles, then the weather, then swaync's notification state.
//
// This is only the content — the silhouette, translucency and drop animation
// come from the BarPanel that hosts it.
Item {
    id: root

    readonly property real panelWidth: 420
    readonly property real panelHeight: 528

    // Mirrors the hosting panel's state. Polling and animations only run while
    // the panel is actually on screen.
    property bool isOpen: false
    signal closeRequested()

    // Place name to look up, e.g. "Belfast, UK". Set from the bar's settings.
    property string location: "Belfast, UK"

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
    property int notificationCount: 0

    // "" is the main page; "wifi" and "bluetooth" replace it with a picker.
    property string page: ""

    Process {
        id: stateProc
        command: ["bash", "-c",
            "w=$(nmcli radio wifi 2>/dev/null); " +
            "b=$(bluetoothctl show 2>/dev/null | grep -c 'Powered: yes'); " +
            "d=$(swaync-client -D 2>/dev/null); " +
            "c=$(pgrep -x hypridle >/dev/null && echo 1 || echo 0); " +
            "n=$(pgrep -x hyprsunset >/dev/null && echo 1 || echo 0); " +
            "echo \"${w:-disabled}|${b:-0}|${d:-false}|$c|$n\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = this.text.trim().split("|")
                if (parts.length < 5)
                    return
                root.wifiOn = parts[0].trim() === "enabled"
                root.bluetoothOn = parseInt(parts[1]) > 0
                root.dndOn = parts[2].trim() === "true"
                // hypridle running means the screen still blanks and locks, so
                // caffeine is the inverse of it.
                root.caffeineOn = parts[3].trim() !== "1"
                root.nightLightOn = parts[4].trim() === "1"
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
            root.pollState()
            root.pollAudio()
            root.refreshWeather()
        } else {
            // Always reopen on the main page.
            root.page = ""
        }
    }

    // ------------------------------------------------------------------
    // WEATHER (Open-Meteo: free, no key, no account)
    // ------------------------------------------------------------------
    property real latitude: NaN
    property real longitude: NaN
    property string resolvedPlace: ""
    property bool weatherLoaded: false
    property string weatherError: ""

    property int currentCode: 0
    property bool currentIsDay: true
    property real currentTemp: 0
    property real todayMin: 0
    property real todayMax: 0
    // Two entries of { day, code, min, max } for the days after today.
    property var forecast: []

    function fmt(t: real): string {
        return Math.round(t) + "°"
    }

    // The location is a free-text place name. Open-Meteo's geocoder takes a
    // bare name, so anything after the first comma is treated as a country
    // hint and used to pick between same-named places rather than being sent.
    function geocode(): void {
        let parts = root.location.split(",")
        let name = parts[0].trim()
        if (name === "")
            return
        geoProc.command = ["bash", "-c",
            "curl -s --max-time 12 'https://geocoding-api.open-meteo.com/v1/search?name="
            + encodeURIComponent(name) + "&count=10&language=en&format=json'"]
        geoProc.running = false
        geoProc.running = true
    }

    Process {
        id: geoProc
        stdout: StdioCollector {
            onStreamFinished: {
                let hint = root.location.split(",").slice(1).join(",").trim().toLowerCase()
                try {
                    let res = JSON.parse(this.text).results
                    if (!res || res.length === 0) {
                        root.weatherError = "Location not found"
                        return
                    }
                    let pick = res[0]
                    if (hint !== "") {
                        for (let i = 0; i < res.length; i++) {
                            let r = res[i]
                            let hay = [r.country, r.country_code, r.admin1]
                                .filter(v => v !== undefined)
                                .join(" ").toLowerCase()
                            if (hay.indexOf(hint) >= 0) {
                                pick = r
                                break
                            }
                        }
                    }
                    root.latitude = pick.latitude
                    root.longitude = pick.longitude
                    root.resolvedPlace = pick.name
                        + (pick.country_code ? ", " + pick.country_code : "")
                    root.weatherError = ""
                    root.fetchWeather()
                } catch (e) {
                    root.weatherError = "Could not reach the weather service"
                }
            }
        }
    }

    function fetchWeather(): void {
        if (isNaN(root.latitude))
            return
        forecastProc.command = ["bash", "-c",
            "curl -s --max-time 12 'https://api.open-meteo.com/v1/forecast?latitude="
            + root.latitude + "&longitude=" + root.longitude
            + "&current=temperature_2m,weather_code,is_day"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&forecast_days=3'"]
        forecastProc.running = false
        forecastProc.running = true
    }

    Process {
        id: forecastProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text)
                    root.currentTemp = d.current.temperature_2m
                    root.currentCode = d.current.weather_code
                    root.currentIsDay = d.current.is_day === 1
                    root.todayMax = d.daily.temperature_2m_max[0]
                    root.todayMin = d.daily.temperature_2m_min[0]

                    let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                    let out = []
                    for (let i = 1; i < d.daily.time.length && i < 3; i++) {
                        out.push({
                            "day": names[new Date(d.daily.time[i] + "T12:00:00").getDay()],
                            "code": d.daily.weather_code[i],
                            "min": d.daily.temperature_2m_min[i],
                            "max": d.daily.temperature_2m_max[i]
                        })
                    }
                    root.forecast = out
                    root.weatherLoaded = true
                    root.weatherError = ""
                } catch (e) {
                    root.weatherError = "Could not read the forecast"
                }
            }
        }
    }

    // Re-geocode when the configured place changes, otherwise just re-fetch.
    function refreshWeather(): void {
        if (isNaN(root.latitude))
            root.geocode()
        else
            root.fetchWeather()
    }

    onLocationChanged: {
        root.latitude = NaN
        root.weatherLoaded = false
        root.geocode()
    }

    Component.onCompleted: root.geocode()

    Timer {
        interval: 20 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: root.refreshWeather()
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

    // A quick-toggle tile: icon over label, filled when the thing is on.
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

    // A labelled level slider, styled like the ones in the sidebar.
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
                onActivated: root.run(Quickshell.env("HOME")
                    + "/.config/hypr/scripts/hypridle.sh toggle")
            }
            Tile {
                iconSrc: "../shared/icons/moon.svg"
                label: "Night Light"
                on: root.nightLightOn
                onActivated: root.run(root.nightLightOn
                    ? "pkill -x hyprsunset"
                    : "hyprsunset >/dev/null 2>&1 &")
            }
            Tile {
                iconSrc: "../shared/icons/clear-all.svg"
                label: "Clear"
                onActivated: root.run("swaync-client -C")
            }
        }

        // --- OUTPUT AND INPUT LEVELS ---
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
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

        Divider {}

        // --- WEATHER ---
        SectionLabel {
            text: root.resolvedPlace !== "" ? root.resolvedPlace.toUpperCase()
                                            : root.location.toUpperCase()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            WeatherIcon {
                Layout.alignment: Qt.AlignVCenter
                size: 54
                code: root.currentCode
                night: !root.currentIsDay
                animate: root.isOpen
                opacity: root.weatherLoaded ? 1 : 0.35
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: root.weatherLoaded ? root.fmt(root.currentTemp) : "--°"
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 30
                    font.bold: true
                }
                Text {
                    text: root.weatherError !== "" ? root.weatherError
                        : (root.weatherLoaded ? weatherGlyph.label : "Loading…")
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
                        text: root.weatherLoaded ? root.fmt(root.todayMin) : "--°"
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
                        text: root.weatherLoaded ? root.fmt(root.todayMax) : "--°"
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
            code: root.currentCode
        }

        // --- NEXT TWO DAYS ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Repeater {
                model: root.forecast

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 52
                    radius: 10
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
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
                                text: root.fmt(modelData.min) + " / " + root.fmt(modelData.max)
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
                visible: root.forecast.length === 0
                Layout.fillWidth: true
                implicitHeight: 52
            }
        }

        Divider {}

        // --- NOTIFICATIONS ---
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

            // swaync owns the notification list and does not expose it over
            // D-Bus, so the list itself stays in its own panel; this opens it.
            Rectangle {
                implicitWidth: openText.implicitWidth + 22
                implicitHeight: 26
                radius: 13
                color: openMouse.containsMouse ? Theme.primary : "transparent"
                border.color: Theme.primary
                border.width: 1
                Behavior on color {
                    ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
                }
                Text {
                    id: openText
                    anchors.centerIn: parent
                    text: root.notificationCount > 0 ? "Show" : "Open"
                    color: openMouse.containsMouse ? Theme.background : Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
                MouseArea {
                    id: openMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["swaync-client", "-t", "-sw"])
                        root.closeRequested()
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.dndOn
                ? "Do Not Disturb is on — notifications are being held back."
                : (root.notificationCount > 0
                    ? root.notificationCount + " waiting in the notification centre."
                    : "Nothing waiting.")
            color: Theme.on_background
            font.family: Theme.fontFamily
            font.pixelSize: 12
            opacity: 0.7
            wrapMode: Text.WordWrap
        }

        Item { Layout.fillHeight: true }
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
}
