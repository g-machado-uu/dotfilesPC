pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

// The desktop's notification daemon. This is what replaced swaync: it owns the
// org.freedesktop.Notifications name, so it has to be the only notification
// server running — swaync is no longer started in conf/autostart.lua, and
// uninstalling it is the point of the exercise.
//
// Deliberately quiet. Nothing pops up on screen: an arriving notification
// pulses the dot under the control centre icon in the bar (see
// StatusbarApp/ControlCentreModule.qml) and waits in the control centre, whose
// "Open" button drops the list out beside it. A notification is kept until it
// is dismissed — the expireTimeout an application asks for is ignored, because
// there is no popup for it to time out of.
//
// One instance for the whole shell (a singleton), shared by every bar.
Singleton {
    id: root

    // ------------------------------------------------------------------
    // THE LIST
    // ------------------------------------------------------------------
    // Newest first, which is the order the panel shows them in. Built by hand
    // rather than with slice().reverse() so the binding tracks `values` (an
    // ObjectModel is only reactive through that property).
    readonly property var list: {
        let out = []
        let v = server.trackedNotifications.values
        for (let i = v.length - 1; i >= 0; i--)
            out.push(v[i])
        return out
    }

    readonly property int count: server.trackedNotifications.values.length

    // Whether anything waiting was sent as urgent. The bar marks these, and
    // they are the one thing Do Not Disturb does not silence.
    readonly property bool hasCritical: {
        let v = server.trackedNotifications.values
        for (let i = 0; i < v.length; i++)
            if (v[i].urgency === NotificationUrgency.Critical)
                return true
        return false
    }

    // When each notification arrived, by id. The specification carries no
    // timestamp, so the server has to remember it for the "5m ago" in the list.
    property var arrivedAt: ({})

    // Raised when a notification arrives and should ask for attention. Do Not
    // Disturb suppresses it for everything except an urgent one.
    signal arrived(var notification)

    // ------------------------------------------------------------------
    // DO NOT DISTURB
    // ------------------------------------------------------------------
    // Notifications still collect in the control centre while this is on; what
    // it stops is the bar asking to be looked at. Kept in its own small file
    // next to ML4W's other settings so it survives a restart, and read back
    // whenever that file changes so every bar agrees.
    property bool dnd: false

    FileView {
        id: dndFile
        path: Quickshell.env("HOME") + "/.config/ml4w/settings/notifications.json"
        watchChanges: true
        onFileChanged: reload()
        printErrors: false
        // The file may be a symlink; a rename-over would replace the link
        // itself (see CLAUDE.md).
        atomicWrites: false
        onLoaded: {
            try {
                let obj = JSON.parse(text())
                if (obj && obj.dnd !== undefined)
                    root.dnd = obj.dnd === true
            } catch (e) {
                // A missing or malformed file just means "not on".
            }
        }
    }

    function setDnd(on: bool): void {
        root.dnd = on
        dndFile.setText(JSON.stringify({ "dnd": on }, null, 4) + "\n")
    }

    function toggleDnd(): void { root.setDnd(!root.dnd) }

    // ------------------------------------------------------------------
    // ACTIONS
    // ------------------------------------------------------------------
    // Close one notification, telling the application the user did it.
    function dismiss(n: var): void {
        if (n)
            n.dismiss()
    }

    // Close every notification. The list is copied first: dismissing removes
    // the notification from the model being walked.
    function clearAll(): void {
        let all = []
        let v = server.trackedNotifications.values
        for (let i = 0; i < v.length; i++)
            all.push(v[i])
        for (let i = 0; i < all.length; i++)
            all[i].dismiss()
    }

    // ------------------------------------------------------------------
    // THE SERVER
    // ------------------------------------------------------------------
    NotificationServer {
        id: server

        // Survive "qs ipc call ..." reloads and theme reloads: notifications
        // from the previous generation are re-sent rather than lost.
        keepOnReload: true

        // What this shell can actually do with a notification, which is what
        // the server advertises to applications.
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        // Notifications are kept until dismissed rather than timed out, so
        // applications can rely on them still being there.
        persistenceSupported: true

        // Not drawn, so not advertised: an action icon, a hyperlink or an
        // image inside the body text would be ignored.
        actionIconsSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        inlineReplySupported: false

        onNotification: notification => {
            // A transient notification is an on-screen hint — a volume or
            // brightness overlay — and is meant to vanish rather than be read
            // later. With no popups there is nowhere to show it, so it is
            // dropped instead of filling the list up.
            if (notification.transient)
                return

            // Keeping it is what puts it in trackedNotifications; without this
            // the server discards it the moment this handler returns.
            notification.tracked = true

            let times = Object.assign({}, root.arrivedAt)
            times[notification.id] = Date.now()
            root.arrivedAt = times

            // Forget the arrival time again when it goes, so the map does not
            // grow for the length of the session.
            notification.closed.connect(() => {
                let t = Object.assign({}, root.arrivedAt)
                delete t[notification.id]
                root.arrivedAt = t
            })

            // Urgent notifications are the exception Do Not Disturb keeps: the
            // whole point of marking one urgent is that it is not routine.
            if (!root.dnd
                || notification.urgency === NotificationUrgency.Critical)
                root.arrived(notification)
        }
    }
}
