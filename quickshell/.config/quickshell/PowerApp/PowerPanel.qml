import Quickshell
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.CustomTheme

// The power actions, laid out as a row so the panel is a short wide card that
// hangs under the power icon in the bar. Sized by content: `panelWidth` /
// `panelHeight` below are what the hosting BarPanel should be given.
FocusScope {
    id: powerRoot

    // Natural size of the card, read by the bar when it sizes the panel.
    readonly property int buttonSize: 46
    readonly property int buttonSpacing: 14
    // Horizontal inset, set by the bar to its own edge margin so the last
    // button lines up under the power icon.
    property int padding: 16
    readonly property int count: 5
    readonly property real panelWidth: count * buttonSize
        + (count - 1) * buttonSpacing + 2 * padding
    readonly property real panelHeight: buttonSize + 32

    // Index of the keyboard-selected button, or -1 for none.
    property int selectedIndex: -1

    // Emitted when an action has been taken, so the bar can close the panel.
    signal actionTaken()

    // Lock goes through logind so hypridle runs its own lock_cmd (hyprlock);
    // with hypridle stopped (caffeine) there is nothing listening, so start
    // hyprlock directly. Logout, reboot and power off go through hyprshutdown,
    // which is how the Hyprland wiki says to leave Hyprland: it asks every app
    // to close first, where exiting the compositor directly just kills them.
    // If logging out leaves a black screen (NVIDIA with SDDM), add
    // "--vt <n>" to the hyprshutdown calls, n being the VT SDDM runs on.
    // Without hyprshutdown installed it falls back to the plain commands.
    function graceful(label: string, postCmd: string, fallback: string): string {
        let args = label === "" ? "" : " -t '" + label + "' --post-cmd '" + postCmd + "'"
        return "if command -v hyprshutdown >/dev/null; then hyprshutdown" + args
            + "; else " + fallback + "; fi"
    }

    readonly property var commands: [
        "if pidof hypridle >/dev/null; then loginctl lock-session; else pidof hyprlock || hyprlock; fi",
        "systemctl suspend",
        graceful("", "", "hyprctl dispatch 'hl.dsp.exit()'"),
        graceful("Restarting...", "reboot", "systemctl reboot"),
        graceful("Shutting down...", "shutdown -P 0", "systemctl poweroff")
    ]

    function run(index: int): void {
        if (index < 0 || index >= powerRoot.commands.length)
            return
        Quickshell.execDetached(["bash", "-c", powerRoot.commands[index]])
        powerRoot.actionTaken()
    }

    // Horizontal now, so the arrows that walk the row are Left/Right. Escape is
    // deliberately not handled here: it falls through to the hosting BarPanel.
    focus: true
    Keys.onLeftPressed: selectedIndex = selectedIndex <= 0 ? count - 1 : selectedIndex - 1
    Keys.onRightPressed: selectedIndex = selectedIndex >= count - 1 ? 0 : selectedIndex + 1
    Keys.onReturnPressed: run(selectedIndex)
    Keys.onEnterPressed: run(selectedIndex)

    // Start with nothing selected each time the panel takes the keyboard, so
    // the first arrow press picks an end of the row rather than resuming where
    // the last visit left off.
    onActiveFocusChanged: {
        if (activeFocus)
            selectedIndex = -1
    }

    component PowerButton: Rectangle {
        id: btn
        property string iconSrc: ""
        property int index: -1

        implicitWidth: powerRoot.buttonSize
        implicitHeight: powerRoot.buttonSize
        radius: width / 2

        readonly property bool active: mouseArea.containsMouse
            || powerRoot.selectedIndex === btn.index

        color: btn.active ? Theme.primary : "transparent"
        border.color: Theme.primary
        border.width: 1

        Behavior on color {
            ColorAnimation { duration: 200; easing.type: Easing.OutQuint }
        }

        Image {
            anchors.centerIn: parent
            source: btn.iconSrc
            width: 21
            height: 21
            sourceSize.width: 21
            sourceSize.height: 21
            fillMode: Image.PreserveAspectFit
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: btn.active ? Theme.background : Theme.primary
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: powerRoot.run(btn.index)
        }
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: powerRoot.buttonSpacing

        PowerButton { index: 0; iconSrc: "../shared/icons/lock.svg" }
        PowerButton { index: 1; iconSrc: "../shared/icons/suspend.svg" }
        PowerButton { index: 2; iconSrc: "../shared/icons/logout.svg" }
        PowerButton { index: 3; iconSrc: "../shared/icons/reboot.svg" }
        PowerButton { index: 4; iconSrc: "../shared/icons/power.svg" }
    }
}
