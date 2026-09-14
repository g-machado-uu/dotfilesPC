import QtQuick
import QtQuick.Effects
import qs.CustomTheme

// The calendar button that stands in for the clock while the desktop widget
// has the time.
//
// The clock module folds itself away when the widget is showing the date and
// time out on the desktop, and the calendar goes with it — the calendar panel
// hangs off the clock. This module is the clock's exact opposite: it unfolds
// into the gap the clock leaves, so the calendar is still one click away, and
// folds itself back out of the way the moment the widget is sucked into the
// bar and the clock returns.
//
// It folds rather than hides for the same reason the clock does: the bar's
// centre modules carry their gap as their own margins, scaled by `fold`, so a
// folding module closes the space around it as it goes instead of leaving a
// hole in the middle of the bar. That also means the two never both take room
// — they trade places, and the bar's width barely moves.
Item {
    id: calRoot

    // Set by the bar: true while the clock has folded away, which is exactly
    // when this button should be out.
    property bool shown: false

    // 0 = fully out, 1 = fully folded away. Read by the bar to scale this
    // module's layout margins in step with its width.
    property real fold: shown ? 0 : 1
    Behavior on fold {
        NumberAnimation { duration: 280; easing.type: Easing.OutQuint }
    }

    // Skipped by the bar's keyboard navigation once it is out of the way.
    readonly property bool collapsed: fold > 0.99
    // Set by the keyboard navigation in StatusbarWindow.
    property bool focused: false

    signal clicked()

    // Run the module's action (mouse click or keyboard Return).
    function activate(): void { calRoot.clicked() }

    // Same 30px touch target as every other module, shrunk by the fold. The
    // button inside keeps its full width, so it slides out of view instead of
    // being squeezed.
    implicitWidth: 30 * (1 - calRoot.fold)
    implicitHeight: 30
    clip: true
    opacity: 1 - calRoot.fold
    enabled: calRoot.fold < 0.5

    readonly property bool active: mouseArea.containsMouse || calRoot.focused

    Rectangle {
        id: pip
        // Anchored to the centre so the button slides out sideways rather than
        // being crushed as the module folds.
        anchors.centerIn: parent
        width: 30
        height: 30
        radius: 15

        // The same accent-filled circle every other bar button gets.
        color: calRoot.active ? Theme.primary : "transparent"
        Behavior on color {
            ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
        }

        Image {
            anchors.centerIn: parent
            source: "../shared/icons/calendar.svg"
            width: 18
            height: 18
            sourceSize.width: 18
            sourceSize.height: 18
            fillMode: Image.PreserveAspectFit
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: calRoot.active ? Theme.background : Theme.primary
                Behavior on colorizationColor {
                    ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: calRoot.activate()
    }
}
