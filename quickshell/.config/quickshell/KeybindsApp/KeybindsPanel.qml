import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.shared

// The keybinding cheat sheet, dropping out of the status bar like the other
// panels (SUPER + CTRL + K). It replaces scripts/keybindings.sh, which piped
// `hyprctl binds` through jq and awk into a two-line rofi list.
//
// The source is the same: `hyprctl binds -j`, keeping only the binds that
// carry a description, which is what makes conf/keybindings/*.lua the single
// place a keybinding is written down. Reading the JSON directly means the
// modifier names are built here rather than in awk, and the list can be
// grouped and searched.
//
// This is only the content — the silhouette, translucency and drop animation
// come from the BarPanel that hosts it.
//
// Keys: type to filter, Up/Down (or Ctrl+J/K, Tab/Shift+Tab) to move,
// PageUp/PageDown to jump, Escape to close.
Item {
    id: root

    readonly property real panelWidth: 560
    readonly property real panelHeight: 560

    property bool isOpen: false
    signal closeRequested()

    // Every open starts from a clean query, at the top, with a fresh read of
    // the binds: they change with a hyprctl reload.
    onIsOpenChanged: {
        if (root.isOpen) {
            search.text = ""
            root.reload()
            search.forceActiveFocus()
        }
    }
    // The panel is only built when it opens (see BarPanel), already open.
    Component.onCompleted: if (root.isOpen) root.reload()

    // The BarPanel hands the keyboard to the content's root; pass it on to the
    // search field so typing filters straight away.
    onActiveFocusChanged: {
        if (root.activeFocus)
            search.forceActiveFocus()
    }

    // ------------------------------------------------------------------
    // READING THE BINDS
    // ------------------------------------------------------------------
    // Every bind Hyprland knows about, as { combo, description, mods, key }.
    property var binds: []

    function reload(): void {
        // Not restarted while a read is already in flight: stopping the
        // process mid-stream ends it with nothing read, and the panel is
        // created and shown in the same moment, so both the open handler and
        // Component.onCompleted ask for the list.
        if (bindsProc.running)
            return
        bindsProc.running = true
    }

    // The modifier bits Hyprland reports in `modmask`, in the order they are
    // written in the keybinding files, so the combo here reads exactly like
    // the one in conf/keybindings/*.lua.
    readonly property var modBits: [
        { "bit": 64, "name": "SUPER" },
        { "bit": 4,  "name": "CTRL" },
        { "bit": 8,  "name": "ALT" },
        { "bit": 1,  "name": "SHIFT" }
    ]

    // Hyprland's own names for keys that have no printable character, tidied
    // into what is on the keycap. Anything not listed is upper-cased as-is.
    readonly property var keyNames: ({
        "return": "ENTER",
        "space": "SPACE",
        "print": "PRINT",
        "escape": "ESC",
        "tab": "TAB",
        "backspace": "BACKSPACE",
        "delete": "DEL",
        "left": "←",
        "right": "→",
        "up": "↑",
        "down": "↓",
        "mouse:272": "LEFT CLICK",
        "mouse:273": "RIGHT CLICK",
        "mouse:274": "MIDDLE CLICK",
        "mouse_up": "WHEEL UP",
        "mouse_down": "WHEEL DOWN",
        "xf86audioraisevolume": "VOL +",
        "xf86audiolowervolume": "VOL −",
        "xf86audiomute": "MUTE",
        "xf86audiomicmute": "MIC MUTE",
        "xf86audioplay": "PLAY",
        "xf86audiopause": "PAUSE",
        "xf86audionext": "NEXT",
        "xf86audioprev": "PREV",
        "xf86monbrightnessup": "BRIGHT +",
        "xf86monbrightnessdown": "BRIGHT −"
    })

    function keyLabel(bind: var): string {
        // `key` carries the keycap name for a key bind and "mouse:272" /
        // "mouse_up" for a pointer one (`mouse` is only a flag saying which).
        // A bind made by keycode has no name at all, so the number stands in.
        let raw = String(bind.key || "")
        if (raw === "")
            return bind.keycode ? "CODE " + bind.keycode : ""
        let known = root.keyNames[raw.toLowerCase()]
        return known !== undefined ? known : raw.toUpperCase()
    }

    function comboLabel(bind: var): string {
        let mods = []
        let mask = parseInt(bind.modmask) || 0
        for (let i = 0; i < root.modBits.length; i++)
            if (mask & root.modBits[i].bit)
                mods.push(root.modBits[i].name)
        let key = root.keyLabel(bind)
        if (key !== "")
            mods.push(key)
        return mods.join(" + ")
    }

    Process {
        id: bindsProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                // A run that was stopped before hyprctl wrote anything.
                if (this.text.trim() === "")
                    return
                let parsed = []
                try {
                    parsed = JSON.parse(this.text)
                } catch (e) {
                    console.warn("keybinds panel: could not parse hyprctl binds:", e)
                    return
                }
                let out = []
                let seen = ({})
                for (let i = 0; i < parsed.length; i++) {
                    let b = parsed[i]
                    // conf/keybindings/*.lua gives every binding worth showing
                    // a description; the rest are plumbing (repeats of the
                    // workspace binds, submaps, passthroughs).
                    if (!b.description || String(b.description).trim() === "")
                        continue
                    let combo = root.comboLabel(b)
                    if (combo === "")
                        continue
                    // The same combo can be bound twice (e.g. once per submap);
                    // one row each is enough.
                    let dedupe = combo + "\u0000" + b.description
                    if (seen[dedupe])
                        continue
                    seen[dedupe] = true
                    out.push({ "combo": combo, "description": String(b.description) })
                }
                out.sort((a, b) => a.combo.localeCompare(b.combo))
                root.binds = out
                root.refilter()
            }
        }
    }

    // ------------------------------------------------------------------
    // FILTERING
    // ------------------------------------------------------------------
    property var results: []
    property int selected: 0

    function refilter(): void {
        const q = search.text.trim().toLowerCase()
        if (q === "") {
            root.results = root.binds
        } else {
            // Every word of the query has to appear somewhere in the row, so
            // "super w" finds the wallpaper binds whichever order they are typed.
            const words = q.split(/\s+/)
            root.results = root.binds.filter(b => {
                const hay = (b.combo + " " + b.description).toLowerCase()
                return words.every(w => hay.includes(w))
            })
        }
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
            placeholderText: "Search keybindings…"
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
                    source: "../shared/icons/keyboard.svg"
                    size: 18
                    color: Theme.primary
                }
            }

            onTextChanged: root.refilter()

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

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "KEYBINDINGS"
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                opacity: 0.7
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.results.length + (root.results.length === 1 ? " bind" : " binds")
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 11
                opacity: 0.5
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.primary; opacity: 0.3 }

        Text {
            visible: root.results.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 40
            horizontalAlignment: Text.AlignHCenter
            text: root.binds.length === 0 ? "No keybindings reported"
                                          : "No matching keybindings"
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

            // Same wheel handling as the launcher and settings panels: a fixed
            // step per notch for a mouse, 1:1 for a touchpad.
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
                height: 40
                radius: 10
                color: row.current ? Qt.alpha(Theme.primary, 0.22)
                    : (rowMouse.containsMouse ? Qt.alpha(Theme.primary, 0.12) : "transparent")
                Behavior on color {
                    ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 12

                    // The combo in its own outlined chip, so the keys read as
                    // keys and the eye can run down the column.
                    Rectangle {
                        Layout.preferredWidth: 184
                        implicitHeight: 24
                        radius: 8
                        color: Qt.alpha(Theme.primary, 0.12)
                        border.color: Theme.primary
                        border.width: 1

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            text: row.modelData.combo
                            color: Theme.primary
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.description
                        color: Theme.on_background
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    // Nothing to click: the list is a reference, not a menu.
                    acceptedButtons: Qt.NoButton
                }
            }
        }
    }
}
