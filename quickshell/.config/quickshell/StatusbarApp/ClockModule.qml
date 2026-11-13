import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme

// Time and date on one line, at the same size and weight as the battery and
// volume readouts so the whole bar reads as a single row of text. The date is
// revealed when the bar expands and folds away again when it collapses, so the
// collapsed pill stays as narrow as it was.
//
// The hairline rule between the time and the date sits exactly at the centre of
// the screen. Both fields are sized to their own text, so the rule sits as far
// left of this module's centre as the date is wider than the time; the module
// reports that difference as `inkSlack`, and the bar's centre group pads its
// own left end by it, which slides the rule back onto the centre line.
//
// An earlier version centred the rule by giving both fields a cell of the same
// width — the wider of the two. That put the rule on the centre line too, but
// it did it by leaving the difference as blank space in front of the time,
// inside this module, which pushed the launcher button a date's-worth further
// from the time than the control centre is from the date. The space is the same
// either way; outside the module it is invisible, and the group reads as
// symmetric.
Item {
    id: clockRoot

    // Set by the parent: when true the date is revealed next to the time.
    property bool expanded: false

    // Set while the desktop widget is showing the time instead, which is when
    // repeating it in the bar would be noise. The module folds itself away
    // sideways rather than disappearing, so the neighbouring modules glide into
    // the space instead of jumping into it.
    property bool hidden: false

    // 0 = fully shown, 1 = fully folded. The bar drives the module's layout
    // margins off this too, so the gap around it closes in step with its width
    // and the fold leaves no hole behind.
    property real fold: hidden ? 1 : 0
    Behavior on fold {
        NumberAnimation { duration: 280; easing.type: Easing.OutQuint }
    }

    // Skipped by the bar's keyboard navigation once it is out of the way.
    readonly property bool collapsed: fold > 0.99
    // Qt date/time format for the time, supplied from statusbar.json.
    property string timeFormat: "HH:mm"
    // Qt date/time format for the date shown beside the time when expanded.
    property string dateFormat: "ddd, dd MMM"
    // Set by the keyboard navigation in StatusbarWindow.
    property bool focused: false

    // Run the module's action (mouse click or keyboard Return).
    // Asks the bar to toggle the calendar panel. The calendar used to be a
    // separate window reached over IPC; it hangs off this module now, so the
    // bar wires this straight through.
    signal toggleRequested()

    function activate(): void {
        clockRoot.toggleRequested()
    }

    // Matches the other modules' 30px touch target.
    implicitWidth: row.implicitWidth * (1 - clockRoot.fold)
    implicitHeight: 30

    // The row keeps its full width while the module shrinks around it, so the
    // text slides out of view instead of being squeezed.
    clip: true
    opacity: 1 - clockRoot.fold
    enabled: clockRoot.fold < 0.5

    // Live clock, only ticks once per minute.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Highlight ring shown when selected via the keyboard.
    Rectangle {
        anchors.fill: row
        anchors.leftMargin: -8
        anchors.rightMargin: -8
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        radius: 8
        color: "transparent"
        border.color: Theme.primary
        border.width: 1
        opacity: clockRoot.focused ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
    }

    // How far the rule sits left of this module's centre, in pixels, and so
    // how much the bar has to pad the left end of its centre group to put the
    // rule back on the centre line. Signed: negative if a time format is ever
    // wider than its date format, which pads the right end instead.
    //
    // Scaled by how far the date is out rather than read from the live cell
    // width, so that it animates with the reveal and keeps its sign the whole
    // way instead of crossing zero as the cell passes the time's width. Goes
    // to zero with the fold, because a folded module has no rule to centre.
    readonly property real dateReveal: dateText.implicitWidth > 0
        ? dateCell.implicitWidth / dateText.implicitWidth : 0
    readonly property real inkSlack:
        (dateText.implicitWidth - timeText.implicitWidth)
        * clockRoot.dateReveal * (1 - clockRoot.fold)

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 0

        // The time, hugging its own text: the rule is centred by the bar's
        // padding, not by blank space in here.
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: timeText.implicitWidth
            implicitHeight: timeText.implicitHeight

            Text {
                id: timeText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, clockRoot.timeFormat)
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                // Tabular digits: "11:11" and "08:08" take the same width.
                font.features: { "tnum": 1 }
            }
        }

        // A hairline rule rather than punctuation: it separates the two fields
        // without reading as part of either. Its width collapses to zero when
        // the date folds away, so the two animate as one.
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: clockRoot.expanded ? 17 : 0
            implicitHeight: 14
            clip: true
            opacity: clockRoot.expanded ? 1 : 0

            Behavior on implicitWidth {
                NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
            }
            Behavior on opacity {
                NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 1
                height: 13
                color: Theme.primary
                opacity: 0.45
            }
        }

        // The date, folded to zero width (and clipped) while collapsed.
        Item {
            id: dateCell
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: clockRoot.expanded ? dateText.implicitWidth : 0
            implicitHeight: dateText.implicitHeight
            clip: true
            opacity: clockRoot.expanded ? 1 : 0

            Behavior on implicitWidth {
                NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
            }
            Behavior on opacity {
                NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
            }

            Text {
                id: dateText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, clockRoot.dateFormat)
                // Same size as the time, lighter weight: the date is context,
                // the time is the thing you actually look for.
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 14
            }
        }
    }

    // Click anywhere on the module toggles the Calendar app via IPC.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: clockRoot.activate()
    }
}
