import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.shared

// The Bluetooth device list, shown in place of the notification panel's main
// page. It connects and disconnects known devices; pairing a brand new one
// still wants a proper agent, so that stays with blueman.
Item {
    id: page

    property bool radioOn: false
    property bool active: false
    property bool scanning: false

    signal back()
    signal toggleRadio()

    ListModel { id: devices }

    onActiveChanged: {
        if (page.active)
            page.refresh()
    }

    // The panel's radio state is polled asynchronously, so `active` usually
    // arrives before `radioOn` does and the refresh above bails out.
    onRadioOnChanged: {
        if (page.active && page.radioOn)
            page.refresh()
    }

    function refresh(): void {
        if (!page.radioOn)
            return
        listProc.running = false
        listProc.running = true
    }

    Timer {
        interval: 6000
        repeat: true
        running: page.active && page.radioOn
        onTriggered: page.refresh()
    }

    Process {
        id: listProc
        // Known devices first, then the connected ones, each line tagged so a
        // single pass can mark which is which.
        command: ["bash", "-c",
            "bluetoothctl devices 2>/dev/null | sed 's/^/K /'; " +
            "bluetoothctl devices Connected 2>/dev/null | sed 's/^/C /'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let known = []
                let connected = ({})
                let lines = this.text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    // "<tag> Device <MAC> <name...>"
                    let m = lines[i].match(/^([KC])\s+Device\s+(\S+)\s+(.*)$/)
                    if (!m)
                        continue
                    if (m[1] === "C")
                        connected[m[2]] = true
                    else
                        known.push({ "mac": m[2], "name": m[3].trim() })
                }
                devices.clear()
                known.sort((a, b) =>
                    (connected[b.mac] ? 1 : 0) - (connected[a.mac] ? 1 : 0))
                for (let j = 0; j < known.length; j++) {
                    devices.append({
                        "mac": known[j].mac,
                        "name": known[j].name,
                        "connected": connected[known[j].mac] === true
                    })
                }
            }
        }
    }

    // bluetoothctl only discovers while a scan is running, so this starts one
    // with a timeout and refreshes when it ends.
    function scan(): void {
        page.scanning = true
        scanProc.running = false
        scanProc.running = true
    }

    Process {
        id: scanProc
        command: ["bash", "-c", "bluetoothctl --timeout 8 scan on >/dev/null 2>&1"]
        onExited: {
            page.scanning = false
            page.refresh()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        PanelPageHeader {
            Layout.fillWidth: true
            title: "Bluetooth"
            toggleOn: page.radioOn
            busy: page.scanning
            onBack: page.back()
            onToggled: page.toggleRadio()
            onRefresh: page.scan()
        }

        Text {
            Layout.fillWidth: true
            visible: !page.radioOn
            text: "Bluetooth is off."
            color: Theme.on_background
            opacity: 0.7
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }

        Text {
            Layout.fillWidth: true
            visible: page.radioOn && devices.count === 0
            text: page.scanning ? "Scanning…"
                : "No known devices. Press refresh to scan, or pair a new device in Bluetooth settings."
            color: Theme.on_background
            opacity: 0.7
            font.family: Theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.radioOn
            clip: true
            spacing: 4
            model: devices

            delegate: Rectangle {
                required property string mac
                required property string name
                required property bool connected

                width: ListView.view.width
                implicitHeight: 40
                radius: 10
                color: connected
                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)
                    : (btMouse.containsMouse
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        : "transparent")
                Behavior on color {
                    ColorAnimation { duration: 150; easing.type: Easing.OutQuint }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 10

                    IconGlyph {
                        source: "../shared/icons/bluetooth.svg"
                        size: 17
                        color: Theme.primary
                        opacity: connected ? 1 : 0.6
                    }

                    Text {
                        Layout.fillWidth: true
                        text: name
                        elide: Text.ElideRight
                        color: Theme.on_background
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: connected
                    }

                    Text {
                        text: connected ? "Connected" : ""
                        color: Theme.primary
                        opacity: 0.75
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: btMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["bash", "-c",
                            "bluetoothctl " + (connected ? "disconnect " : "connect ") + mac])
                        settle.restart()
                    }
                }
            }
        }
    }

    Timer {
        id: settle
        interval: 1800
        onTriggered: page.refresh()
    }
}
