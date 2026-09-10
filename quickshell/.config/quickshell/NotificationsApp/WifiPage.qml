import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.shared

// The Wi-Fi picker, shown in place of the notification panel's main page.
// Everything goes through nmcli, so it needs nothing beyond NetworkManager.
Item {
    id: page

    property bool radioOn: false
    // Only scans and repaints while it is the visible page.
    property bool active: false

    signal back()
    signal toggleRadio()

    // SSID currently being connected to, and the one waiting for a password.
    property string connectingTo: ""
    property string passwordFor: ""
    property string errorText: ""

    ListModel { id: networks }

    onActiveChanged: {
        if (page.active) {
            page.errorText = ""
            page.passwordFor = ""
            page.rescan()
        }
    }

    // The panel's radio state is polled asynchronously, so `active` usually
    // arrives before `radioOn` does and the scan above bails out. Scanning
    // again when the radio turns on covers both that and switching it on by
    // hand while the page is up.
    onRadioOnChanged: {
        if (page.active && page.radioOn)
            page.rescan()
    }

    // A rescan takes a few seconds to settle, so the list is read again after
    // the scan has had time to finish rather than immediately.
    function rescan(): void {
        if (!page.radioOn)
            return
        Quickshell.execDetached(["nmcli", "device", "wifi", "rescan"])
        listProc.running = false
        listProc.running = true
        settle.restart()
    }

    Timer {
        id: settle
        interval: 2500
        onTriggered: {
            listProc.running = false
            listProc.running = true
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: page.active && page.radioOn
        onTriggered: {
            listProc.running = false
            listProc.running = true
        }
    }

    Process {
        id: listProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY",
                  "device", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                // IN-USE:SSID:SIGNAL:SECURITY, one per line. Hidden networks
                // come through with an empty SSID and are dropped; the same
                // SSID can appear once per band, so only the strongest is kept.
                let best = ({})
                let order = []
                let lines = this.text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    let f = lines[i].split(":")
                    if (f.length < 4)
                        continue
                    let ssid = f[1].trim()
                    if (ssid === "")
                        continue
                    let entry = {
                        "ssid": ssid,
                        "signal": parseInt(f[2]) || 0,
                        "secured": f[3].trim() !== "",
                        "inUse": f[0].indexOf("*") >= 0
                    }
                    if (best[ssid] === undefined) {
                        best[ssid] = entry
                        order.push(ssid)
                    } else if (entry.signal > best[ssid].signal
                               || entry.inUse) {
                        best[ssid] = {
                            "ssid": ssid,
                            "signal": Math.max(entry.signal, best[ssid].signal),
                            "secured": entry.secured,
                            "inUse": entry.inUse || best[ssid].inUse
                        }
                    }
                }
                order.sort((a, b) => {
                    if (best[a].inUse !== best[b].inUse)
                        return best[a].inUse ? -1 : 1
                    return best[b].signal - best[a].signal
                })
                networks.clear()
                for (let j = 0; j < order.length; j++)
                    networks.append(best[order[j]])
            }
        }
    }

    // Single quotes are the shell quoting here, so any quote inside the SSID
    // has to be broken out of and re-quoted.
    function shellQuote(s: string): string {
        return "'" + String(s).split("'").join("'\\''") + "'"
    }

    function connect(ssid: string, password: string): void {
        page.connectingTo = ssid
        page.errorText = ""
        let cmd = "nmcli device wifi connect " + page.shellQuote(ssid)
        if (password !== "")
            cmd += " password " + page.shellQuote(password)
        connectProc.command = ["bash", "-c", cmd + " 2>&1"]
        connectProc.running = false
        connectProc.running = true
    }

    Process {
        id: connectProc
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text
                let failed = out.indexOf("Error:") >= 0
                if (!failed) {
                    page.passwordFor = ""
                    page.errorText = ""
                } else if (out.indexOf("Secrets") >= 0
                           || out.toLowerCase().indexOf("password") >= 0) {
                    // Saved credentials were missing or wrong: ask for them.
                    page.passwordFor = page.connectingTo
                    page.errorText = ""
                } else {
                    page.errorText = out.replace(/^Error:\s*/, "").split("\n")[0]
                }
                page.connectingTo = ""
                listProc.running = false
                listProc.running = true
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        PanelPageHeader {
            Layout.fillWidth: true
            title: "Wi-Fi"
            toggleOn: page.radioOn
            busy: page.connectingTo !== ""
            onBack: page.back()
            onToggled: page.toggleRadio()
            onRefresh: page.rescan()
        }

        Text {
            Layout.fillWidth: true
            visible: page.errorText !== ""
            text: page.errorText
            color: Theme.primary
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            visible: !page.radioOn
            text: "Wi-Fi is off."
            color: Theme.on_background
            opacity: 0.7
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.radioOn
            clip: true
            spacing: 4
            model: networks

            delegate: Item {
                required property string ssid
                required property int signal
                required property bool secured
                required property bool inUse
                width: ListView.view.width
                implicitHeight: column.implicitHeight

                ColumnLayout {
                    id: column
                    width: parent.width
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 10
                        color: inUse
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)
                            : (rowMouse.containsMouse
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
                                source: "../shared/icons/wifi.svg"
                                size: 17
                                color: Theme.primary
                                opacity: 0.35 + 0.65 * (signal / 100)
                            }

                            Text {
                                Layout.fillWidth: true
                                text: ssid
                                elide: Text.ElideRight
                                color: Theme.on_background
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: inUse
                            }

                            Text {
                                visible: secured
                                text: "🔒"
                                font.pixelSize: 10
                                opacity: 0.6
                            }

                            Text {
                                text: signal + "%"
                                color: Theme.primary
                                opacity: 0.7
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (inUse)
                                    return
                                page.passwordFor = ""
                                page.connect(ssid, "")
                            }
                        }
                    }

                    // Revealed only for the network whose connection attempt
                    // came back asking for secrets.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 12
                        Layout.bottomMargin: 4
                        visible: page.passwordFor === ssid
                        spacing: 8

                        TextField {
                            id: pw
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: "Password"
                            color: Theme.on_background
                            placeholderTextColor: Qt.rgba(Theme.on_background.r,
                                Theme.on_background.g, Theme.on_background.b, 0.45)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            background: Rectangle {
                                radius: 8
                                color: "transparent"
                                border.color: Theme.primary
                                border.width: 1
                            }
                            onAccepted: page.connect(ssid, text)
                            onVisibleChanged: if (visible) forceActiveFocus()
                        }

                        Rectangle {
                            implicitWidth: 62
                            implicitHeight: 30
                            radius: 8
                            color: joinMouse.containsMouse ? Theme.primary : "transparent"
                            border.color: Theme.primary
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "Join"
                                color: joinMouse.containsMouse ? Theme.background : Theme.primary
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: joinMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.connect(ssid, pw.text)
                            }
                        }
                    }
                }
            }
        }
    }
}
