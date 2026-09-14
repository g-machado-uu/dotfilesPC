import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.shared

// The appearance page, shown in place of the control centre's main page. It
// took over the old sidebar's theme and desktop controls.
//
// Every row names exactly what it changes. The panel's own colours come from
// the wallpaper (matugen) and nothing here switches them, so the dark style is
// labelled as the apps' style rather than as a "theme".
Item {
    id: page

    // Only polls while it is the visible page.
    property bool active: false
    // The desktop time/weather widget, owned by the status bar.
    property bool weatherWidgetOn: true

    signal back()
    // Asked for before launching something that takes the screen or the
    // pointer (an app window, the colour picker).
    signal closeRequested()

    property bool darkOn: false
    property bool hyprmodInstalled: false

    readonly property string home: Quickshell.env("HOME")

    Process {
        id: darkProc
        command: ["bash", "-c",
            "grep -Eq 'gtk-application-prefer-dark-theme *= *(1|true)' "
            + "\"$HOME/.config/gtk-3.0/settings.ini\" && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: page.darkOn = this.text.trim() === "1"
        }
    }

    Process {
        id: hyprmodProc
        command: ["bash", "-c", "command -v hyprmod >/dev/null && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: page.hyprmodInstalled = this.text.trim() === "1"
        }
    }

    // Re-read once the toggle script has written the file.
    Timer {
        id: settle
        interval: 800
        onTriggered: {
            darkProc.running = false
            darkProc.running = true
        }
    }

    onActiveChanged: {
        if (!page.active)
            return
        darkProc.running = false
        darkProc.running = true
        hyprmodProc.running = false
        hyprmodProc.running = true
    }

    function launch(cmd: string): void {
        page.closeRequested()
        Quickshell.execDetached(["bash", "-c", cmd])
    }

    component SectionLabel: Text {
        color: Theme.primary
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
        opacity: 0.7
    }

    component Divider: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.primary
        opacity: 0.22
    }

    // A title with a line of detail under it; the row's control is whatever
    // the instance adds after it.
    component SettingRow: RowLayout {
        id: row
        property string title: ""
        property string detail: ""

        Layout.fillWidth: true
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: row.title
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 13
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: row.detail
                color: Theme.on_background
                font.family: Theme.fontFamily
                font.pixelSize: 11
                opacity: 0.7
                elide: Text.ElideRight
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        PanelPageHeader {
            Layout.fillWidth: true
            title: "Appearance"
            showRefresh: false
            showToggle: false
            onBack: page.back()
        }

        // --- APPS ---
        SectionLabel { text: "APPS" }

        SettingRow {
            title: "Dark style"
            detail: "GTK apps · Super+Shift+M"
            ToggleSwitch {
                on: page.darkOn
                onToggled: {
                    page.darkOn = !page.darkOn
                    // The toggle only edits settings.ini; gtk.sh pushes it to
                    // gsettings so running apps follow at once.
                    Quickshell.execDetached(["bash", "-c",
                        page.home + "/.config/ml4w/scripts/ml4w-toggle-theme && "
                        + page.home + "/.config/hypr/scripts/gtk.sh"])
                    settle.restart()
                }
            }
        }

        SettingRow {
            title: "GTK theme"
            detail: "Theme, icons, cursor and font · nwg-look"
            PillButton {
                text: "Open"
                onActivated: page.launch("nwg-look")
            }
        }

        SettingRow {
            title: "Qt theme"
            detail: "Style, icons and font · qt6ct"
            PillButton {
                text: "Open"
                onActivated: page.launch("qt6ct")
            }
        }

        Divider {}

        // --- DESKTOP ---
        SectionLabel { text: "DESKTOP" }

        SettingRow {
            title: "Weather widget"
            detail: "Clock and forecast on empty workspaces"
            ToggleSwitch {
                on: page.weatherWidgetOn
                // The bar owns statusbar.json; the new state comes back
                // through weatherWidgetOn.
                onToggled: Quickshell.execDetached(["qs", "ipc", "call", "statusbar",
                    page.weatherWidgetOn ? "disableWeatherWidget" : "enableWeatherWidget"])
            }
        }

        Divider {}

        // --- TOOLS ---
        SectionLabel { text: "TOOLS" }

        SettingRow {
            title: "Colour picker"
            detail: "Pick a colour anywhere on screen · hyprpicker"
            PillButton {
                text: "Pick"
                onActivated: page.launch(page.home + "/.config/ml4w/settings/hyprpicker.sh")
            }
        }

        SettingRow {
            visible: page.hyprmodInstalled
            title: "HyprMod"
            detail: "Hyprland settings editor"
            PillButton {
                text: "Open"
                onActivated: page.launch("hyprmod")
            }
        }

        Item { Layout.fillHeight: true }
    }
}
