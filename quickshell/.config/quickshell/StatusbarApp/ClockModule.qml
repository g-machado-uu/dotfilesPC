import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme

// Time and date on one line, at the same size and weight as the battery and
// volume readouts so the whole bar reads as a single row of text. The date is
// revealed when the bar expands and folds away again when it collapses, so the
// collapsed pill stays as narrow as it was.
Item {
    id: clockRoot

    // Set by the parent: when true the date is revealed next to the time.
    property bool expanded: false
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
    implicitWidth: row.implicitWidth
    implicitHeight: 30

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

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Text {
            id: timeText
            Layout.alignment: Qt.AlignVCenter
            text: Qt.formatDateTime(clock.date, clockRoot.timeFormat)
            color: Theme.primary
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.bold: true
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
