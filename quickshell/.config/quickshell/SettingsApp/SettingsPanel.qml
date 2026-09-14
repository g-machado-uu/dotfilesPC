import Quickshell
import Quickshell.Io
import QtQml
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme

// The settings that used to live in the separate ML4W Dotfiles Settings app,
// as a panel that drops out of the status bar like the control centre.
//
// This is only the content — the silhouette, translucency and drop animation
// come from the BarPanel that hosts it.
//
// What is listed comes from settings.json next to this file. Every entry names
// a file and how its value sits in it: "overwrite" means the whole file is the
// value, "replace" means the value is the ".*" part of the "match" pattern.
// A third mode, "command", owns no file at all: the value is read from
// "read_command" and written by "write_command" with "%s" standing for the
// (shell-quoted) value — for settings whose file belongs to another app, like
// the status bar's own statusbar.json.
// Entries with "requires": "arch" are only shown on Arch-based systems.
Item {
    id: root

    readonly property real panelWidth: 440

    // Mirrors the hosting panel's state.
    property bool isOpen: false
    signal closeRequested()

    readonly property string home: Quickshell.env("HOME")

    function expand(path: string): string {
        return path.startsWith("~/") ? root.home + path.substring(1) : path
    }

    function fallback(setting: var): string {
        return setting.default !== undefined ? String(setting.default) : ""
    }

    // ------------------------------------------------------------------
    // SCHEMA
    // ------------------------------------------------------------------
    property var groups: []
    property int groupIndex: 0

    FileView {
        path: String(Qt.resolvedUrl("settings.json")).replace("file://", "")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.groups = JSON.parse(text())
            } catch (e) {
                console.warn("SettingsPanel: settings.json is not valid JSON:", e)
            }
        }
    }

    // The AUR helper only means something on Arch and its derivatives, which
    // name "arch" in ID or ID_LIKE.
    property bool isArch: false

    FileView {
        path: "/etc/os-release"
        onLoaded: {
            let ids = []
            for (const line of text().split("\n")) {
                const m = line.match(/^(ID|ID_LIKE)=(.*)$/)
                if (m)
                    ids = ids.concat(m[2].replace(/"/g, "").split(/\s+/))
            }
            root.isArch = ids.indexOf("arch") >= 0
        }
    }

    readonly property var currentGroup: root.groups[root.groupIndex] || null
    readonly property var visibleSettings: root.currentGroup
        ? root.currentGroup.settings.filter(s => s.requires !== "arch" || root.isArch)
        : []

    // ------------------------------------------------------------------
    // READING AND WRITING VALUES
    // ------------------------------------------------------------------
    // Single-quote a value for "command" settings, so a place name with a
    // space or an apostrophe reaches the command in one piece.
    function shellQuote(s: string): string {
        return "'" + s.replace(/'/g, "'\\''") + "'"
    }

    function escapeRegExp(s: string): string {
        return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    }

    // "border-width: .*px" -> /border-width: (.*)px/
    function pattern(match: string, flags: string): var {
        const i = match.indexOf(".*")
        return new RegExp(root.escapeRegExp(match.substring(0, i)) + "(.*)"
            + root.escapeRegExp(match.substring(i + 2)), flags)
    }

    function readValue(setting: var, content: string): string {
        if (setting.mode === "overwrite") {
            const t = content.trim()
            return t === "" ? root.fallback(setting) : t
        }
        const m = content.match(root.pattern(setting.match, ""))
        return m ? m[1] : root.fallback(setting)
    }

    function writeValue(setting: var, content: string, value: string): string {
        if (setting.mode === "overwrite")
            return value + "\n"
        const i = setting.match.indexOf(".*")
        const before = setting.match.substring(0, i)
        const after = setting.match.substring(i + 2)
        // A replacer function, so a "$" in the value is never read as a
        // back-reference.
        return content.replace(root.pattern(setting.match, "g"), () => before + value + after)
    }

    // Arrows switch tabs while nothing inside has the keyboard. Escape falls
    // through to the hosting BarPanel.
    focus: true
    Keys.onLeftPressed: root.groupIndex = Math.max(0, root.groupIndex - 1)
    Keys.onRightPressed: root.groupIndex = Math.min(root.groups.length - 1, root.groupIndex + 1)

    // ------------------------------------------------------------------
    // COMPONENTS
    // ------------------------------------------------------------------
    component ChoiceItem: MenuItem {
        id: item
        contentItem: Text {
            text: item.text
            font.family: Theme.fontFamily
            font.pixelSize: 14
            color: item.highlighted ? Theme.background : Theme.primary
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            implicitWidth: 200
            implicitHeight: 34
            radius: 4
            color: item.highlighted ? Theme.primary : "transparent"
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        Text {
            text: "Settings"
            color: Theme.primary
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.bold: true
        }

        // --- GROUP TABS ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: root.groups

                delegate: Rectangle {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property bool selected: tab.index === root.groupIndex

                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 15
                    color: tab.selected ? Theme.primary
                        : (tabMouse.containsMouse ? Qt.alpha(Theme.primary, 0.15) : "transparent")
                    border.color: Theme.primary
                    border.width: 1
                    Behavior on color {
                        ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: tab.modelData.group
                        color: tab.selected ? Theme.background : Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: tab.selected
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.groupIndex = tab.index
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.currentGroup ? root.currentGroup.description : ""
            visible: text !== ""
            color: Theme.on_background
            opacity: 0.75
            font.family: Theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.primary; opacity: 0.3 }

        // --- SETTINGS ---
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.visibleSettings

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                visible: list.contentHeight > list.height
                interactive: true
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: 3
                    color: Theme.primary
                    opacity: parent.pressed ? 1.0 : (parent.active ? 0.8 : 0.4)
                }
            }

            delegate: Item {
                id: row
                required property var modelData
                readonly property var setting: row.modelData

                width: list.width - 12
                implicitHeight: 48

                property string value: root.fallback(row.setting)
                property bool fileMissing: false
                // A "command" setting is read and written by running something,
                // not by touching a file, so the FileView below stays idle.
                readonly property bool isCommand: row.setting.mode === "command"
                property var options: row.setting.type === "choose" ? row.setting.options : []
                property bool postPending: false

                FileView {
                    id: file
                    path: row.isCommand ? "" : root.expand(row.setting.file)
                    watchChanges: true
                    // Write in place rather than via a temp file and rename, so
                    // a file that is itself a symlink stays one.
                    atomicWrites: false
                    printErrors: false
                    onFileChanged: reload()
                    onLoaded: {
                        row.fileMissing = false
                        row.value = root.readValue(row.setting, text())
                    }
                    onLoadFailed: {
                        row.fileMissing = true
                        row.value = root.fallback(row.setting)
                    }
                    onSaved: {
                        savedFlash.restart()
                        if (row.postPending && row.setting.post_command) {
                            row.postPending = false
                            Quickshell.execDetached(["bash", "-c", row.setting.post_command])
                        }
                    }
                }

                // "command" settings read their current value by running one.
                Process {
                    command: ["bash", "-c", row.setting.read_command || "true"]
                    running: row.isCommand && root.isOpen
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const t = this.text.trim()
                            if (t !== "")
                                row.value = t
                        }
                    }
                }

                function apply(v: string): void {
                    if (v === "" || v === row.value)
                        return
                    if (row.isCommand) {
                        Quickshell.execDetached(["bash", "-c",
                            String(row.setting.write_command).replace("%s", root.shellQuote(v))])
                        row.value = v
                        savedFlash.restart()
                        return
                    }
                    // A pattern can only be replaced inside a file that exists.
                    if (row.setting.mode !== "overwrite" && row.fileMissing)
                        return
                    row.postPending = true
                    file.setText(root.writeValue(row.setting, row.fileMissing ? "" : file.text(), v))
                    row.value = v
                }

                // Variant pickers list the files in their folder.
                Process {
                    command: ["ls", "-1", root.expand(row.setting.folder || "")]
                    running: row.setting.type === "files" && root.isOpen
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const ext = row.setting.filetypes || ""
                            row.options = this.text.split("\n")
                                .filter(n => n !== "" && (ext === "" || n.endsWith(ext)))
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.rightMargin: 4
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        // Fills the width (with the spacer at the end) so the
                        // column can grow and every control lines up on the right.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: row.setting.name
                                color: Theme.primary
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                            }
                            Text {
                                id: savedTag
                                text: "Saved"
                                opacity: 0
                                color: Theme.on_background
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                SequentialAnimation {
                                    id: savedFlash
                                    NumberAnimation { target: savedTag; property: "opacity"; to: 0.8; duration: 120 }
                                    PauseAnimation { duration: 900 }
                                    NumberAnimation { target: savedTag; property: "opacity"; to: 0; duration: 300 }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !row.isCommand && row.fileMissing && row.setting.mode !== "overwrite"
                            text: "Not found: " + row.setting.file
                            color: Theme.on_background
                            opacity: 0.6
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                    }

                    // --- CHOICE (fixed list, or the files in a folder) ---
                    Rectangle {
                        id: choice
                        visible: row.setting.type === "choose" || row.setting.type === "files"
                        Layout.preferredWidth: 190
                        implicitHeight: 32
                        radius: 8
                        color: choiceMouse.containsMouse ? Qt.alpha(Theme.primary, 0.15) : "transparent"
                        border.color: Theme.primary
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                // Variant files read better without ".lua".
                                text: row.value.replace(/\.lua$/, "")
                                color: Theme.primary
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            Text {
                                text: "▾"
                                color: Theme.primary
                                font.pixelSize: 12
                            }
                        }

                        MouseArea {
                            id: choiceMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: menu.open()
                        }

                        Menu {
                            id: menu
                            y: choice.height + 4
                            width: choice.width
                            padding: 6
                            // Keeps the menu inside the panel; a long list scrolls.
                            margins: 8
                            background: Rectangle {
                                color: Theme.background
                                border.color: Theme.primary
                                border.width: 1
                                radius: 8
                            }

                            Instantiator {
                                model: row.options
                                delegate: ChoiceItem {
                                    required property var modelData
                                    text: String(modelData).replace(/\.lua$/, "")
                                    onTriggered: row.apply(String(modelData))
                                }
                                onObjectAdded: (index, object) => menu.insertItem(index, object)
                                onObjectRemoved: (index, object) => menu.removeItem(object)
                            }
                        }
                    }

                    // --- FREE TEXT (commands, fonts) ---
                    TextField {
                        id: field
                        visible: row.setting.type === "textfield"
                        Layout.preferredWidth: 190
                        implicitHeight: 32
                        text: row.value
                        placeholderText: root.fallback(row.setting)
                        color: Theme.primary
                        placeholderTextColor: Qt.alpha(Theme.primary, 0.5)
                        selectionColor: Theme.primary
                        selectedTextColor: Theme.background
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        leftPadding: 10
                        rightPadding: 10
                        // Saved on Enter and when the field loses focus.
                        onEditingFinished: row.apply(text.trim())
                        background: Rectangle {
                            radius: 8
                            color: "transparent"
                            border.color: Theme.primary
                            border.width: field.activeFocus ? 2 : 1
                        }
                    }
                }
            }
        }
    }
}
