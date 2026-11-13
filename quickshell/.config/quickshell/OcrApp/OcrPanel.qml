import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.shared

// The OCR language picker, dropping out of the status bar like the other
// panels (SUPER + ALT + A). It replaces the rofi menu that used to sit in the
// middle of scripts/text-extractor.sh.
//
// The script still owns everything else: it knows which tesseract languages
// are installed (--list-langs, which is what fills this list) and it does the
// capture itself once a language has been chosen (--lang). So there is only
// ever one list of languages, and it is the installed one.
//
// Picking a language closes the panel and *then* starts the capture, because
// the script puts hyprpicker and slurp over the whole screen — the panel has
// to be out of the way, and off screen, before that happens.
//
// This is only the content — the silhouette, translucency and drop animation
// come from the BarPanel that hosts it.
Item {
    id: root

    readonly property real panelWidth: 300
    // Header, divider and a row per language, inside the margins.
    readonly property real panelHeight: 52 + 20
        + Math.max(1, root.languages.length) * 38 + 2 * 18

    property bool isOpen: false
    signal closeRequested()

    // Re-read on every open: a language pack can be installed meanwhile.
    onIsOpenChanged: {
        if (root.isOpen) {
            root.selected = 0
            root.reload()
        }
    }
    // The panel is only built when it opens (see BarPanel), already open.
    Component.onCompleted: if (root.isOpen) root.reload()

    readonly property string script:
        Quickshell.env("HOME") + "/.config/hypr/scripts/text-extractor.sh"

    // ------------------------------------------------------------------
    // THE INSTALLED LANGUAGES
    // ------------------------------------------------------------------
    // Three-letter tesseract codes, as the script reports them.
    property var languages: []
    property int selected: 0

    function reload(): void {
        // Same guard as the keybinds panel: a restart mid-stream would end the
        // read with nothing in it.
        if (langProc.running)
            return
        langProc.running = true
    }

    Process {
        id: langProc
        command: ["bash", "-c", "'" + root.script + "' --list-langs"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "")
                    return
                let out = []
                let lines = this.text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    let code = lines[i].trim()
                    if (code !== "")
                        out.push(code)
                }
                root.languages = out
                root.selected = 0
            }
        }
    }

    // The tesseract codes are ISO 639-2/T, which say nothing on their own.
    // Only the ones a language pack exists for are worth naming; anything else
    // falls back to the code itself.
    readonly property var langNames: ({
        "afr": "Afrikaans", "ara": "Arabic", "bel": "Belarusian",
        "ben": "Bengali", "bul": "Bulgarian", "cat": "Catalan",
        "ces": "Czech", "chi_sim": "Chinese (simplified)",
        "chi_tra": "Chinese (traditional)", "dan": "Danish", "deu": "German",
        "ell": "Greek", "eng": "English", "epo": "Esperanto",
        "est": "Estonian", "eus": "Basque", "fas": "Persian",
        "fin": "Finnish", "fra": "French", "gle": "Irish",
        "glg": "Galician", "heb": "Hebrew", "hin": "Hindi",
        "hrv": "Croatian", "hun": "Hungarian", "ind": "Indonesian",
        "isl": "Icelandic", "ita": "Italian", "jpn": "Japanese",
        "kat": "Georgian", "kor": "Korean", "lat": "Latin",
        "lav": "Latvian", "lit": "Lithuanian", "mkd": "Macedonian",
        "msa": "Malay", "nld": "Dutch", "nor": "Norwegian",
        "pol": "Polish", "por": "Portuguese", "ron": "Romanian",
        "rus": "Russian", "slk": "Slovak", "slv": "Slovenian",
        "spa": "Spanish", "sqi": "Albanian", "srp": "Serbian",
        "swa": "Swahili", "swe": "Swedish", "tam": "Tamil",
        "tel": "Telugu", "tha": "Thai", "tur": "Turkish",
        "ukr": "Ukrainian", "urd": "Urdu", "vie": "Vietnamese",
        "wel": "Welsh", "cym": "Welsh"
    })

    function langName(code: string): string {
        let known = root.langNames[code]
        return known !== undefined ? known : code
    }

    // ------------------------------------------------------------------
    // CAPTURING
    // ------------------------------------------------------------------
    // The language to capture with, held while the panel closes.
    property string pending: ""

    function pick(code: string): void {
        if (code === "")
            return
        root.pending = code
        root.closeRequested()
        // Long enough for the panel's close animation to finish and the
        // surface to go away, so hyprpicker's overlay and slurp's region never
        // land on top of it.
        captureDelay.restart()
    }

    Timer {
        id: captureDelay
        interval: 320
        onTriggered: {
            if (root.pending === "")
                return
            Quickshell.execDetached(["bash", "-c",
                "'" + root.script + "' --lang " + root.pending])
            root.pending = ""
        }
    }

    function move(delta: int): void {
        if (root.languages.length === 0)
            return
        root.selected = Math.max(0, Math.min(root.languages.length - 1,
                                             root.selected + delta))
    }

    // The BarPanel hands the keyboard to this item, so the arrow keys and
    // Return work without the mouse.
    focus: true
    Keys.onUpPressed: root.move(-1)
    Keys.onDownPressed: root.move(1)
    Keys.onReturnPressed: root.pick(root.languages[root.selected] || "")
    Keys.onEnterPressed: root.pick(root.languages[root.selected] || "")

    // ------------------------------------------------------------------
    // LAYOUT
    // ------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconGlyph {
                Layout.alignment: Qt.AlignVCenter
                source: "../shared/icons/scan-text.svg"
                size: 20
                color: Theme.primary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: "Extract Text"
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                }

                Text {
                    text: "Pick a language, then drag a region"
                    color: Theme.on_background
                    opacity: 0.6
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.primary; opacity: 0.3 }

        Text {
            visible: root.languages.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 10
            horizontalAlignment: Text.AlignHCenter
            text: "No tesseract languages installed"
            color: Theme.on_background
            opacity: 0.5
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }

        Repeater {
            model: root.languages

            Rectangle {
                id: row
                required property string modelData
                required property int index
                readonly property bool current: row.index === root.selected

                Layout.fillWidth: true
                implicitHeight: 34
                radius: 10
                color: rowMouse.containsMouse ? Theme.primary
                    : (row.current ? Qt.alpha(Theme.primary, 0.18) : "transparent")
                Behavior on color {
                    ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    IconGlyph {
                        Layout.alignment: Qt.AlignVCenter
                        source: "../shared/icons/languages.svg"
                        size: 14
                        color: rowMouse.containsMouse ? Theme.background : Theme.primary
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.langName(row.modelData)
                        color: rowMouse.containsMouse ? Theme.background : Theme.on_background
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }

                    // The code itself, so an unnamed language is still
                    // identifiable and a named one is still verifiable.
                    Text {
                        text: row.modelData
                        color: rowMouse.containsMouse ? Theme.background : Theme.primary
                        opacity: 0.6
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pick(row.modelData)
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
