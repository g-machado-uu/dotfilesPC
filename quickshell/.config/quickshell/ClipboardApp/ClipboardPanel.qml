import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import qs.CustomTheme

// Clipboard history, dropping out of its icon in the status bar. This is only
// the content: the silhouette, the translucency and the drop animation come
// from the BarPanel that hosts it.
Item {
    id: root

    // Natural size of the panel body, read by the bar when it sizes the drop.
    readonly property real panelWidth: 400
    readonly property real panelHeight: 440

    // Mirrors the hosting panel's state; the history is re-read on each open.
    property bool isOpen: false
    signal closeRequested()
    function close(): void { root.closeRequested() }

    onIsOpenChanged: {
        if (root.isOpen)
            root.refreshClipboard()
    }

    ListModel { id: clipModel }

    function refreshClipboard(): void {
        clipModel.clear()
        listProc.running = false
        listProc.running = true
    }

    Process {
        id: listProc
        command: ["bash", "-c", "cliphist list | head -50"]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim()
                    if (line.length === 0)
                        continue
                    let tabIdx = line.indexOf("\t")
                    if (tabIdx < 0)
                        continue
                    let id = line.substring(0, tabIdx)
                    let content = line.substring(tabIdx + 1)
                    let isBinary = content.startsWith("[[ binary data")
                    clipModel.append({
                        clipId: id,
                        clipText: isBinary ? content : content,
                        isBinary: isBinary
                    })
                }
            }
        }
    }

    function selectItem(clipId: string): void {
        pasteProc.command = ["bash", "-c", "cliphist decode " + clipId + " | wl-copy"]
        pasteProc.running = true
        root.close()
    }

    function clearHistory(): void {
        clearProc.running = true
    }

    Process {
        id: pasteProc
        running: false
    }

    Process {
        id: clearProc
        command: ["cliphist", "wipe"]
        onExited: refreshClipboard()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Image {
                source: "../shared/icons/clipboard.svg"
                sourceSize.width: 20
                sourceSize.height: 20
                width: 20
                height: 20
                fillMode: Image.PreserveAspectFit
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: Theme.primary
                }
            }

            Text {
                text: "Clipboard History"
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
                Layout.fillWidth: true
            }

            Button {
                implicitWidth: 28
                implicitHeight: 28
                background: Rectangle {
                    color: parent.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                    radius: 6
                }
                contentItem: Text {
                    text: "↻"
                    color: Theme.primary
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.refreshClipboard()
                ToolTip.visible: hovered
                ToolTip.text: "Refresh"
            }

            Button {
                implicitWidth: 28
                implicitHeight: 28
                background: Rectangle {
                    color: parent.hovered ? Qt.rgba(1, 0.3, 0.3, 0.2) : "transparent"
                    radius: 6
                }
                contentItem: Text {
                    text: "✕"
                    color: Theme.primary
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.clearHistory()
                ToolTip.visible: hovered
                ToolTip.text: "Clear all"
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.primary
            opacity: 0.3
        }

        Text {
            visible: clipModel.count === 0
            text: "No clipboard history"
            color: Theme.on_background
            opacity: 0.5
            font.family: Theme.fontFamily
            font.pixelSize: 13
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            Layout.topMargin: 40
        }

        ListView {
            id: clipList
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: clipModel
            clip: true
            spacing: 4

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Rectangle {
                id: clipItem
                required property int index
                required property string clipId
                required property string clipText
                required property bool isBinary

                width: clipList.width
                height: 40
                radius: 6
                color: itemMouse.containsMouse
                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                    : "transparent"

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: clipItem.isBinary ? "📎 " + clipItem.clipText : clipItem.clipText
                        color: Theme.on_background
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        visible: itemMouse.containsMouse
                        text: "⏎"
                        color: Theme.primary
                        font.pixelSize: 14
                        opacity: 0.7
                    }
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectItem(clipItem.clipId)
                }
            }
        }
    }
}
