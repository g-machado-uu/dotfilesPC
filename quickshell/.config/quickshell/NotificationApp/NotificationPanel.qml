import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.shared

// The notification list, dropping out of the status bar beside the control
// centre: the control centre's "Open" button is what brings it out, and the
// two then sit side by side with the pair centred under the bar.
//
// The notifications themselves live in NotificationService, the shell's
// notification daemon, so this panel is only a view of them — closing it keeps
// everything waiting, and a notification arriving while it is open appears at
// the top.
//
// This is only the content — the silhouette, translucency and drop animation
// come from the BarPanel that hosts it.
Item {
    id: root

    readonly property real panelWidth: 380
    readonly property real panelHeight: 520

    // The rule under the header, in panel coordinates. The stem that joins this
    // card to the control centre flares down to meet the card's edge exactly
    // here, so the joint lands on the line that separates the header from the
    // list instead of at an arbitrary height.
    readonly property real dividerY: body.y + divider.y

    property bool isOpen: false
    signal closeRequested()

    // Only ticks while the panel is up, which is the only time the "5m ago"
    // labels are on screen.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        enabled: root.isOpen
    }

    // How long ago a notification arrived, in the shortest form that still
    // says it. Notifications carry no timestamp of their own; the service
    // remembers when each one came in.
    function ago(id: int): string {
        let then = NotificationService.arrivedAt[id]
        if (then === undefined)
            return ""
        let mins = Math.floor((clock.date.getTime() - then) / 60000)
        if (mins < 1)
            return "now"
        if (mins < 60)
            return mins + "m ago"
        let hours = Math.floor(mins / 60)
        if (hours < 24)
            return hours + "h ago"
        return Math.floor(hours / 24) + "d ago"
    }

    // The application's own icon, falling back to the generic one. An image
    // sent with the notification (an album cover, a contact photo) wins over
    // the application icon.
    function iconFor(n: var): string {
        if (n.image && n.image !== "")
            return n.image
        if (n.appIcon && n.appIcon !== "")
            return Quickshell.iconPath(n.appIcon, "dialog-information")
        return Quickshell.iconPath("dialog-information", true)
    }

    // Run one of the notification's buttons. A "resident" notification asks to
    // stay after one of its actions is used; any other is finished with.
    function invoke(n: var, action: var): void {
        if (!action)
            return
        action.invoke()
        if (!n.resident)
            n.dismiss()
    }

    // ------------------------------------------------------------------
    // LAYOUT
    // ------------------------------------------------------------------
    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // --- HEADER ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconGlyph {
                Layout.alignment: Qt.AlignVCenter
                source: NotificationService.dnd
                    ? "../shared/icons/bell-off.svg"
                    : "../shared/icons/bell.svg"
                size: 20
                color: Theme.primary
            }

            Text {
                Layout.fillWidth: true
                text: "Notifications"
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
            }

            Text {
                visible: NotificationService.dnd
                text: "DND"
                color: Theme.primary
                opacity: 0.6
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }

            PillButton {
                text: "Clear all"
                enabled: NotificationService.count > 0
                onActivated: NotificationService.clearAll()
            }
        }

        Rectangle {
            id: divider
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.primary
            opacity: 0.3
        }

        // --- EMPTY STATE ---
        // Centred with anchors rather than as a nested layout. A ColumnLayout
        // whose children all carry a Layout.alignment reports *their* widest
        // implicit width as its own maximum, so Layout.fillWidth cannot stretch
        // it and the whole block ends up hugging the left edge (measured: 95px
        // wide in a 348px panel). An anchored Column has no such subtlety.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: NotificationService.count === 0

            Column {
                anchors.centerIn: parent
                spacing: 8

                IconGlyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: "../shared/icons/bell.svg"
                    size: 28
                    color: Theme.on_background
                    opacity: 0.25
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Nothing waiting"
                    color: Theme.on_background
                    opacity: 0.5
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }
            }
        }

        // --- THE LIST ---
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: NotificationService.count > 0
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: NotificationService.list
            // Rows are as tall as their text, so the view cannot guess.
            cacheBuffer: 400

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

            // The bar's wheel handling: a fixed step per notch for a mouse,
            // 1:1 for a touchpad (see CLAUDE.md).
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
                id: card
                required property var modelData
                readonly property var n: card.modelData
                readonly property bool urgent:
                    card.n.urgency === NotificationUrgency.Critical

                width: list.width
                implicitHeight: cardBody.implicitHeight + 20
                height: implicitHeight
                radius: 12
                color: cardMouse.containsMouse
                    ? Qt.alpha(Theme.primary, 0.14)
                    : Qt.alpha(Theme.primary, 0.07)
                // An urgent notification is outlined rather than coloured in:
                // the accent is the only colour the bar has, and filling the
                // card with it would make the row unreadable.
                border.color: Theme.primary
                border.width: card.urgent ? 1 : 0

                Behavior on color {
                    ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
                }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }

                ColumnLayout {
                    id: cardBody
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    anchors.topMargin: 10
                    spacing: 4

                    // --- APPLICATION, TIME, DISMISS ---
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Image {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            sourceSize.width: 16
                            sourceSize.height: 16
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            source: root.iconFor(card.n)
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: card.n.appName !== "" ? card.n.appName : "Notification"
                            color: Theme.primary
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.maximumWidth: 150
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            readonly property string label: root.ago(card.n.id)
                            visible: label !== ""
                            text: "· " + label
                            color: Theme.on_background
                            opacity: 0.5
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }

                        Item { Layout.fillWidth: true }

                        // Close this one. Only while the pointer is on the
                        // card, so a quiet list stays quiet.
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 20
                            implicitHeight: 20
                            radius: 10
                            opacity: cardMouse.containsMouse || dismissMouse.containsMouse ? 1 : 0
                            color: dismissMouse.containsMouse
                                ? Theme.primary : "transparent"

                            Behavior on opacity {
                                NumberAnimation { duration: 150 }
                            }

                            IconGlyph {
                                anchors.centerIn: parent
                                source: "../shared/icons/x.svg"
                                size: 12
                                color: dismissMouse.containsMouse
                                    ? Theme.background : Theme.primary
                            }

                            MouseArea {
                                id: dismissMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: NotificationService.dismiss(card.n)
                            }
                        }
                    }

                    // --- SUMMARY ---
                    Text {
                        Layout.fillWidth: true
                        visible: card.n.summary !== ""
                        text: card.n.summary
                        color: Theme.on_background
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        // The summary is a plain line by specification; drawing
                        // it as markup would let stray "<" through as a tag.
                        textFormat: Text.PlainText
                    }

                    // --- BODY ---
                    Text {
                        Layout.fillWidth: true
                        visible: card.n.body !== ""
                        text: card.n.body
                        color: Theme.on_background
                        opacity: 0.75
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        maximumLineCount: 6
                        elide: Text.ElideRight
                        // The body may carry the small markup subset the server
                        // advertises (bold, italic, links).
                        textFormat: Text.StyledText
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }

                    // --- ACTIONS ---
                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        visible: card.n.actions.length > 0
                        spacing: 6

                        Repeater {
                            model: card.n.actions

                            PillButton {
                                required property var modelData
                                // The specification's "default" action is what
                                // clicking the notification body would do; it
                                // is not meant to be shown as a button.
                                visible: modelData.identifier !== "default"
                                text: modelData.text !== ""
                                    ? modelData.text : modelData.identifier
                                onActivated: root.invoke(card.n, modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
