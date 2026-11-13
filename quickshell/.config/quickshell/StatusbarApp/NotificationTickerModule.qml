import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.shared
import qs.NotificationApp

// The newest waiting notification, in the bar, next to the media slot.
//
// This is the one place the shell says what a notification is rather than only
// that one exists: the dot under the control centre icon counts them, this
// reads out the latest. It shows the application's icon and the notification's
// text, rolling sideways when the text is longer than the slot.
//
// It is not a popup and it does not steal focus, and it never changes the size
// of the bar: its slot is a constant width, held whether or not anything is
// waiting, exactly as the media slot is. The bar's width is built from its
// three groups, so a slot that came and went would widen the bar every time
// something arrived and narrow it again when it was dismissed. Here nothing
// moves: the notification fades and slides in on the spot, and its text rolls
// inside the room the slot already has.
//
// Under Do Not Disturb it stays folded away. Notifications still collect and
// the control centre still counts them; what Do Not Disturb turns off is
// exactly this sort of asking to be read.
//
//   click        the notification centre, or — for a notification that names
//                a file, such as a finished download — that file's folder,
//                with the file selected
//   right click  dismiss this notification (the next one slides in)
//   wheel        step through the waiting notifications
Item {
    id: ticker

    // The width of the slot, held constant. Everything here is sized from it,
    // and nothing here is ever allowed to ask for more.
    property real available: 240

    // No gap in front of this module, for the same reason as the media slot:
    // its own 10px of padding is the gap. Read by the bar's left area.
    readonly property real gapBefore: 0
    // Skipped by the bar's keyboard navigation with nothing to show, while the
    // slot itself stays — as with the media module.
    readonly property bool collapsed: ticker.folded
    // Set by the keyboard navigation in StatusbarWindow.
    property bool focused: false

    // What is left for the text once the icon and the padding have had theirs.
    readonly property real textSpace:
        Math.max(0, ticker.available - (16 + row.spacing + 20))

    // Which waiting notification is being shown. The newest by default; the
    // wheel steps back through the others, and the index is clamped back into
    // range whenever the list changes under it (one being dismissed, or a new
    // one arriving at the front).
    property int index: 0
    readonly property var notes: NotificationService.list
    readonly property var note:
        ticker.index >= 0 && ticker.index < ticker.notes.length
            ? ticker.notes[ticker.index] : null

    onNotesChanged: {
        if (ticker.index > 0 && ticker.index >= ticker.notes.length)
            ticker.index = Math.max(0, ticker.notes.length - 1)
    }
    // A new arrival is what the module is for: show it rather than keeping the
    // place in the list the wheel had reached.
    Connections {
        target: NotificationService
        function onArrived(notification): void {
            ticker.index = 0
            // Also when the new one reads the same as the one already up, in
            // which case the label does not change and would not roll.
            burst.restart()
        }
    }

    // --- COMING AND GOING ---
    // Nothing in the bar moves for this: it fades and slides in on the spot,
    // in space the bar was already holding open.
    readonly property bool present:
        ticker.note !== null && !NotificationService.dnd && ticker.textSpace > 40
    property real reveal: ticker.present ? 1 : 0
    Behavior on reveal {
        NumberAnimation { duration: 280; easing.type: Easing.OutQuint }
    }
    readonly property bool folded: ticker.reveal < 0.004

    // --- WHAT IT SAYS ---
    // Summary and body on one line. The body's newlines go: this is a single
    // line of text in a bar, and a notification that wraps belongs in the
    // panel, which is one click away.
    readonly property string label: {
        if (!ticker.note)
            return ""
        let head = (ticker.note.summary || "").replace(/\s+/g, " ").trim()
        let rest = (ticker.note.body || "").replace(/\s+/g, " ").trim()
        if (head === "")
            return rest
        if (rest === "" || rest === head)
            return head
        return head + "  ·  " + rest
    }

    readonly property string iconSource: {
        if (!ticker.note)
            return ""
        if (ticker.note.image && ticker.note.image !== "")
            return ticker.note.image
        if (ticker.note.appIcon && ticker.note.appIcon !== "")
            return Quickshell.iconPath(ticker.note.appIcon, "dialog-information")
        return Quickshell.iconPath("dialog-information", true)
    }

    // --- THE FILE A NOTIFICATION IS ABOUT ---
    // Where downloads land, so a "download complete" that names only a file
    // name can still be pointed at. Asked of xdg-user-dir once, because it is
    // a user setting rather than a constant (~/Downloads is only the default).
    property string downloadDir: Quickshell.env("HOME") + "/Downloads"
    Process {
        running: true
        command: ["xdg-user-dir", "DOWNLOAD"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = this.text.trim()
                if (d !== "")
                    ticker.downloadDir = d
            }
        }
    }

    // The file this notification is about, or "" for one that is not about a
    // file. Three ways of naming one, in order of how certain they are:
    //
    //   1. a file:// URI anywhere in the text
    //   2. an absolute path anywhere in the text (the screenshot and the
    //      wallpaper notifications both carry one)
    //   3. a finished download, which usually names the file and not the
    //      folder: the file name is taken to be in the download folder
    //
    // Nothing here touches the disk. A path that has since been moved away
    // opens its folder with nothing selected, which is still the right folder.
    readonly property string filePath: ticker.note ? ticker.pathFor(ticker.note) : ""

    function pathFor(n: var): string {
        let text = (n.summary || "") + "\n" + (n.body || "")

        let m = text.match(/file:\/\/(\/[^\s"'<>]+)/)
        if (m)
            return decodeURIComponent(m[1])

        m = text.match(/\/(?:home|root|srv|opt|mnt|media|tmp|var)\/[^\s"'<>]+/)
        if (m)
            return m[0]

        if (/\bdownload(ed|s)?\b/i.test(text)
                && /\b(complete|completed|finished|done|saved|ready)\b/i.test(text)) {
            // The file name is whichever field is not the "download finished"
            // phrase itself, so both orders work.
            let candidates = [(n.body || "").trim(), (n.summary || "").trim()]
            for (let i = 0; i < candidates.length; i++) {
                let name = candidates[i].split("\n")[0].trim()
                if (name !== "" && name.indexOf("/") < 0
                        && /\.[A-Za-z0-9]{1,8}$/.test(name))
                    return ticker.downloadDir + "/" + name
            }
        }
        return ""
    }

    // Show a file in the file manager, selected, through the freedesktop
    // interface every file manager implements for exactly this (nautilus,
    // dolphin, thunar, nemo). It is D-Bus activated, so the file manager does
    // not have to be running.
    //
    // The path is percent-encoded into a URI first, which is what makes it
    // safe to put inside the GVariant literal gdbus wants: an encoded URI has
    // no quotes, spaces or brackets left in it.
    function showInFileManager(path: string): void {
        let uri = "file://" + path.split("/").map(encodeURIComponent).join("/")
        Quickshell.execDetached(["gdbus", "call", "--session",
            "--dest", "org.freedesktop.FileManager1",
            "--object-path", "/org/freedesktop/FileManager1",
            "--method", "org.freedesktop.FileManager1.ShowItems",
            '["' + uri + '"]', ""])
    }

    // --- ACTIONS ---
    // Asks the bar for the notification centre. Raised for a notification that
    // is not about a file; one that is opens that file's folder instead.
    signal openRequested()

    function activate(): void {
        if (ticker.filePath !== "") {
            ticker.showInFileManager(ticker.filePath)
            return
        }
        ticker.openRequested()
    }

    function dismiss(): void {
        NotificationService.dismiss(ticker.note)
    }

    // --- THE SLOT ---
    readonly property bool hovered: mouseArea.containsMouse && !ticker.folded
    readonly property bool active: ticker.hovered
        || (ticker.focused && !ticker.folded)

    // The slot is constant; the pill inside it is as wide as what is in it.
    implicitWidth: ticker.available
    implicitHeight: 30

    // The hover pill, as wide as what is actually in it: icon, gap, text slot
    // and the padding either side. A short notification is a short pill; a long
    // one fills the room there is and rolls inside it.
    Rectangle {
        id: body
        width: 16 + row.spacing + viewport.width + 20
        height: 30
        radius: 15
        clip: true

        color: ticker.active ? Theme.primary : "transparent"
        Behavior on color {
            ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
        }

        opacity: ticker.reveal
        // Slides in from the left as it fades, which is the whole of the
        // arrival: no geometry anywhere else in the bar changes.
        transform: Translate { x: -14 * (1 - ticker.reveal) }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Image {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            sourceSize.width: 16
            sourceSize.height: 16
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            source: ticker.iconSource
        }

        // The text slot: a fixed-width window onto a line that may be longer
        // than it is.
        Item {
            id: viewport
            Layout.alignment: Qt.AlignVCenter
            // As wide as the line, or as wide as there is room for — whichever
            // is less. That is what makes a short notification hug and a long
            // one roll.
            Layout.preferredWidth:
                Math.min(label.implicitWidth, ticker.textSpace)
            Layout.maximumWidth: ticker.textSpace
            implicitHeight: label.implicitHeight
            clip: true

            // How far the line overruns the slot, and so how far it has to
            // travel. Zero for a line that fits, which is what stops the roll.
            readonly property real overflow:
                Math.max(0, label.implicitWidth - viewport.width)

            Text {
                id: label
                y: 0
                width: implicitWidth
                anchors.verticalCenter: parent.verticalCenter
                text: ticker.label
                // A notification's summary and body are the sender's text, not
                // markup to be interpreted in the bar.
                textFormat: Text.PlainText
                color: ticker.active ? Theme.background : Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            // Roll out and back, pausing at each end long enough to read the
            // start and the finish. The speed is a constant 34 px/s rather
            // than a constant duration, so a long notification does not race
            // past.
            //
            // It does not roll forever. A notification that has been sitting
            // unread for an hour does not need to keep moving, and moving text
            // is not free: measured against this shell, a rolling line costs
            // about 2.4% of a core, against 0.08% for the bar at rest. So it
            // rolls for a while after it arrives — long enough to read a long
            // line through twice — and then settles back to the beginning. Put
            // the pointer on it to read the rest at any time.
            //
            // Never while the module is folding, either: a text that moves
            // inside a clip rectangle that is itself changing size makes Qt
            // rebuild its render batches every frame, which is the one thing
            // this bar is careful not to do.
            Timer {
                id: burst
                interval: 40000
                running: false
            }

            SequentialAnimation {
                id: roll
                running: viewport.overflow > 0 && ticker.reveal >= 1
                    && (ticker.hovered || burst.running)
                loops: Animation.Infinite
                alwaysRunToEnd: false
                onRunningChanged: if (!roll.running) label.x = 0

                PauseAnimation { duration: 2200 }
                NumberAnimation {
                    target: label
                    property: "x"
                    to: -viewport.overflow
                    duration: Math.round(viewport.overflow / 34 * 1000)
                    easing.type: Easing.InOutQuad
                }
                PauseAnimation { duration: 2200 }
                NumberAnimation {
                    target: label
                    property: "x"
                    to: 0
                    duration: Math.round(viewport.overflow / 34 * 1000)
                    easing.type: Easing.InOutQuad
                }
            }

            // A new line to read: back to its beginning, and roll it.
            onOverflowChanged: if (viewport.overflow <= 0) label.x = 0
            Connections {
                target: ticker
                function onLabelChanged(): void {
                    label.x = 0
                    burst.restart()
                }
            }
        }
    }

        // On the pill itself, so the clickable area is exactly what is drawn.
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            enabled: !ticker.folded && ticker.reveal > 0.9
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    ticker.dismiss()
                else
                    ticker.activate()
            }
            // Step through the waiting notifications without opening anything.
            onWheel: wheel => {
                if (ticker.notes.length < 2)
                    return
                let step = wheel.angleDelta.y > 0 ? -1 : 1
                ticker.index = Math.max(0, Math.min(ticker.notes.length - 1,
                                                    ticker.index + step))
            }
        }
    }
}
