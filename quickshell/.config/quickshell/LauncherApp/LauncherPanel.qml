import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.shared

// The application launcher, dropping out of the status bar like the other
// panels: a rofi `drun` replacement that reads the same .desktop files through
// Quickshell's DesktopEntries.
//
// This is only the content — the silhouette, translucency and drop animation
// come from the BarPanel that hosts it.
//
// Keys: type to filter, Up/Down (or Ctrl+J/K, Tab/Shift+Tab) to move,
// PageUp/PageDown to jump, Return to launch, Escape to close.
//
// Apps you launch are counted (in Quickshell's state directory) and float to
// the top, both of the empty list and of the matches for a query.
Item {
    id: root

    readonly property real panelWidth: 520
    readonly property real panelHeight: 520

    property bool isOpen: false
    signal closeRequested()

    // Every open starts from a clean query at the top of the list.
    onIsOpenChanged: {
        if (root.isOpen) {
            search.text = ""
            root.refilter()
            search.forceActiveFocus()
        }
    }
    // The panel is only built when it opens (see BarPanel).
    Component.onCompleted: root.refilter()

    // The BarPanel hands the keyboard to the content's root; pass it on to
    // the search field so typing works straight away.
    onActiveFocusChanged: {
        if (root.activeFocus)
            search.forceActiveFocus()
    }

    // ------------------------------------------------------------------
    // USAGE COUNTS
    // ------------------------------------------------------------------
    property var usage: ({})

    FileView {
        id: usageFile
        path: Quickshell.statePath("launcher-usage.json")
        printErrors: false
        onLoaded: {
            try {
                root.usage = JSON.parse(text()) || {}
            } catch (e) {
                root.usage = {}
            }
            root.refilter()
        }
    }

    function bumpUsage(id: string): void {
        let u = Object.assign({}, root.usage)
        u[id] = (u[id] || 0) + 1
        root.usage = u
        usageFile.setText(JSON.stringify(u))
    }

    // ------------------------------------------------------------------
    // FILTERING
    // ------------------------------------------------------------------
    property var results: []
    property int selected: 0

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged(): void { root.refilter() }
    }

    // True when every character of q appears in s, in order.
    function subsequence(q: string, s: string): bool {
        let j = 0
        for (let i = 0; i < s.length && j < q.length; i++)
            if (s[i] === q[j])
                j++
        return j === q.length
    }

    function score(e: var, q: string): int {
        const name = (e.name || "").toLowerCase()
        if (name.startsWith(q))
            return 1000
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
            return 800
        if (name.includes(q))
            return 600
        const generic = (e.genericName || "").toLowerCase()
        const keywords = (e.keywords || []).join(" ").toLowerCase()
        if (generic.includes(q) || keywords.includes(q))
            return 400
        const id = (e.id || "").toLowerCase()
        const comment = (e.comment || "").toLowerCase()
        if (id.includes(q) || comment.includes(q))
            return 200
        if (root.subsequence(q, name))
            return 100
        return 0
    }

    function refilter(): void {
        const q = search.text.trim().toLowerCase()
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay)
        let ranked = []
        for (const e of apps) {
            const s = q === "" ? 1 : root.score(e, q)
            if (s > 0)
                ranked.push({ entry: e, s: s + Math.min(root.usage[e.id] || 0, 50) * (q === "" ? 1 : 4) })
        }
        ranked.sort((a, b) => b.s - a.s || a.entry.name.localeCompare(b.entry.name))
        root.results = ranked.map(r => r.entry)
        root.selected = 0
        list.positionViewAtBeginning()
    }

    function move(delta: int): void {
        if (root.results.length === 0)
            return
        root.selected = Math.max(0, Math.min(root.results.length - 1, root.selected + delta))
        list.positionViewAtIndex(root.selected, ListView.Contain)
    }

    // ------------------------------------------------------------------
    // LAUNCHING
    // ------------------------------------------------------------------
    // The terminal named in the settings panel (Default apps → Terminal).
    FileView {
        id: terminalFile
        path: Quickshell.env("HOME") + "/.config/ml4w/settings/terminal.sh"
        printErrors: false
    }

    function launch(e: var): void {
        if (!e)
            return
        root.bumpUsage(e.id)
        if (e.runInTerminal) {
            const term = (terminalFile.text() || "kitty").trim().split(/\s+/)
            Quickshell.execDetached({
                command: term.concat(["-e"]).concat(e.command),
                workingDirectory: e.workingDirectory || Quickshell.env("HOME")
            })
        } else {
            e.execute()
        }
        root.closeRequested()
    }

    // ------------------------------------------------------------------
    // LAYOUT
    // ------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // --- SEARCH ---
        TextField {
            id: search
            Layout.fillWidth: true
            implicitHeight: 40
            placeholderText: "Search applications…"
            color: Theme.primary
            placeholderTextColor: Qt.alpha(Theme.primary, 0.5)
            selectionColor: Theme.primary
            selectedTextColor: Theme.background
            font.family: Theme.fontFamily
            font.pixelSize: 15
            leftPadding: 42
            rightPadding: 14
            background: Rectangle {
                radius: 20
                color: Qt.alpha(Theme.primary, 0.08)
                border.color: Theme.primary
                border.width: search.activeFocus ? 2 : 1

                IconGlyph {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    source: "../shared/icons/launcher.svg"
                    size: 18
                    color: Theme.primary
                }
            }

            onTextChanged: root.refilter()
            onAccepted: root.launch(root.results[root.selected])

            Keys.onUpPressed: root.move(-1)
            Keys.onDownPressed: root.move(1)
            Keys.onTabPressed: root.move(1)
            Keys.onBacktabPressed: root.move(-1)
            Keys.onPressed: event => {
                if (event.modifiers & Qt.ControlModifier) {
                    if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                        root.move(1); event.accepted = true
                    } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                        root.move(-1); event.accepted = true
                    }
                } else if (event.key === Qt.Key_PageDown) {
                    root.move(8); event.accepted = true
                } else if (event.key === Qt.Key_PageUp) {
                    root.move(-8); event.accepted = true
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.primary; opacity: 0.3 }

        Text {
            visible: root.results.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 40
            horizontalAlignment: Text.AlignHCenter
            text: "No matching applications"
            color: Theme.on_background
            opacity: 0.5
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }

        // --- RESULTS ---
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.results
            currentIndex: root.selected
            // Only the rows on screen (plus a little) exist at any time, so the
            // icons of a few hundred apps are never all decoded at once.
            cacheBuffer: 120
            highlightFollowsCurrentItem: false

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                visible: list.contentHeight > list.height
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: 3
                    color: Theme.primary
                    opacity: parent.pressed ? 1.0 : (parent.active ? 0.8 : 0.4)
                }
            }

            // Same wheel handling as the settings panel: a fixed step per
            // notch for a mouse, 1:1 for a touchpad.
            WheelHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const deltaY = event.pixelDelta.y !== 0
                        ? event.pixelDelta.y
                        : event.angleDelta.y / 120 * 100
                    if (!deltaY)
                        return
                    const maxY = list.originY + Math.max(0, list.contentHeight - list.height)
                    list.contentY = Math.max(list.originY, Math.min(maxY, list.contentY - deltaY))
                }
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool current: row.index === root.selected

                width: list.width
                height: 52
                radius: 12
                color: row.current ? Theme.primary
                    : (rowMouse.containsMouse ? Qt.alpha(Theme.primary, 0.15) : "transparent")
                Behavior on color {
                    ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    Image {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        sourceSize.width: 32
                        sourceSize.height: 32
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            color: row.current ? Theme.background : Theme.on_background
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: row.current
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            readonly property string sub: row.modelData.genericName || row.modelData.comment || ""
                            visible: sub !== ""
                            text: sub
                            color: row.current ? Theme.background : Theme.on_background
                            opacity: 0.65
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        visible: row.current
                        text: "⏎"
                        color: Theme.background
                        font.pixelSize: 14
                        opacity: 0.8
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.launch(row.modelData)
                }
            }
        }
    }
}
