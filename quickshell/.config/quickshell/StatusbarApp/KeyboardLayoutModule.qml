import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.CustomTheme

// Shows the current keyboard layout (e.g., gb, br).
Rectangle {
    id: keyboard

    property bool focused: false
    property string layout: "GB"
    
    signal clicked()
    function activate(): void { keyboard.clicked() }

    implicitWidth: contentRow.implicitWidth + 10
    implicitHeight: 28
    radius: 15
    
    // Highlighted when hovered or selected via keyboard.
    readonly property bool active: mouseArea.containsMouse || keyboard.focused
    color: keyboard.active ? Theme.primary : "transparent"
    
    Behavior on color {
        ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
    }

    function normalizeLayoutName(name: string): string {
        let lower = name.toLowerCase()
        if (lower.includes("brazil") || lower.includes("portuguese"))
            return "⌨ BR"
        if (lower.includes("english") || lower.includes("british"))
            return "⌨ GB"
        let trimmed = name.trim()
        if (trimmed.length >= 2)
            return trimmed.slice(0, 2).toUpperCase()
        return "⌨ GB"
    }

    // Get the current keyboard layout from the system.
    function updateLayout(): void {
        layoutProc.running = false
        layoutProc.running = true
    }

    Component.onCompleted: updateLayout()

    RowLayout {
        id: contentRow
        anchors.centerIn: parent
        spacing: 0

        Text {
            text: keyboard.layout
            color: keyboard.active ? Theme.background : Theme.primary
            font.pixelSize: 11
            font.weight: Font.Bold
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            
            Behavior on color {
                ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: keyboard.clicked()
    }

    // Periodically update layout to detect changes
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: updateLayout()
    }

    Process {
        id: layoutProc
        command: ["bash", "-c",
            "hyprctl devices -j 2>/dev/null | jq -r '.keyboards[] | select(.main == true) | .active_keymap // empty' | head -n1"]

        stdout: StdioCollector {
            onStreamFinished: {
                let output = this.text.trim()
                if (output.length > 0)
                    keyboard.layout = keyboard.normalizeLayoutName(output)
            }
        }
    }
}
