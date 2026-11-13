import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import qs.CustomTheme
import qs.shared
import qs.CalendarApp
import qs.PowerApp
import qs.ClipboardApp
import qs.ControlCentreApp
import qs.MediaApp
import qs.WallpaperApp
import qs.SettingsApp
import qs.SoundApp
import qs.SystemApp
import qs.LauncherApp
import qs.KeybindsApp
import qs.NotificationApp
import qs.OcrApp

PanelWindow {
    id: root

    // --- WAYLAND CONFIGURATION ---
    WlrLayershell.layer: WlrLayer.Top
    // Keyboard focus is owned by the HyprlandFocusGrab below (the same primitive
    // the Calendar/Power popups use), not by the layer-shell focus mode. A
    // WlrKeyboardFocus.Exclusive grab held the keyboard until Escape and left
    // running apps dead; OnDemand never grabbed from the keybinding at all. The
    // focus grab gives the bar the keyboard while expanded *and* fires onCleared
    // when the pointer/keyboard goes to another window, which is what hands focus
    // back to the app (and collapses the bar). Leave the layer-shell mode at its
    // default (None) so the two mechanisms don't fight.

    // Grabs the keyboard for the bar while it is expanded so SUPER + SPACE can
    // drive Left/Right/Return navigation, and releases it the moment the user
    // interacts with another window (clicking/entering an app) — which returns
    // the keyboard to that app and collapses the bar.
    HyprlandFocusGrab {
        windows: [root]
        active: root.barExpanded
        onCleared: root.barExpanded = false
    }

    // --- USER SETTINGS ---
    // One of two files is the "master" that feeds the settings object below:
    //
    //   1. ~/.config/quickshell/StatusbarApp/statusbar.json — the user override. When this
    //      file EXISTS it is the master: every value is read from it and the
    //      IPC setters write their changes (enabled, alwaysExpanded, weather)
    //      back into it. The shipped file is ignored while it exists.
    //   2. ~/.config/ml4w/settings/statusbar.json — the shipped fallback, used
    //      only when the override file is absent. It carries the dynamic state
    //      the IPC setters write (bar.enabled, bar.alwaysExpanded, weather).
    //
    // The active master file is merged over the built-in defaults, so a partial
    // or entirely missing file still leaves every value defined.
    readonly property var defaultSettings: ({
        "bar":    { "height": 36, "reservedHeight": 36, "enabled": true, "alwaysExpanded": false },
        "pill":   { "collapsedWidth": 0, "expandedWidth": 600, "radius": 18, "flareRadius": 18, "animationDuration": 350 },
        "modules":{ "left": ["terminal", "workspaces", "media", "notificationticker"],
                    "center": ["launcher", "clock", "calendar", "controlcentre","updates"],
                    "right": ["battery", "powerprofile", "volume", "systemtray", "keyboard", "clipboard", "power"] },
        "border": { "width": 0, "colorTop": "", "colorBottom": "" },
        "opacity":{ "collapsed": 0.82, "expanded": 0.9 },
        "clock":  { "format": "HH:mm", "dateFormat": "ddd, dd MMM" },
        "workspaces": { "count": 5, "showAppIcons": true },
        // Free-text place name for the notification panel's weather. Anything
        // after the first comma is a hint used to pick between same-named
        // places (e.g. "Belfast, UK" vs "Belfast, US").
        // desktopWidget: whether the time/weather widget is allowed onto an
        // empty workspace at all. Off means the bar keeps the clock at all
        // times and the widget never appears.
        // widgetScale: size of the desktop widget (1.0 = original size).
        // showDelay: ms a workspace must stay empty before the widget comes
        // out, so apps that blink their window while loading don't bounce it.
        "weather": { "location": "Belfast, UK", "desktopWidget": true,
                     "widgetScale": 0.8, "showDelay": 600 },
        // spawnDuration: how long the notification card takes to grow out of
        // the control centre, and to be sucked back in, in milliseconds.
        // Deliberately not called animationDuration: the persist helpers match
        // a key by name across the whole document, and the pill already has one.
        "notifications": { "spawnDuration": 320, "tickerWidth": 150 },
        // The two wide slots in the left group. They are what the bar's width
        // is actually made of: see the note on pill.expandedWidth.
        "media":  { "titleWidth": 90 }
    })

    property var settings: defaultSettings

    // True while the user override file is present. Decides which file is the
    // master for both reads (applySettings) and writes (setEnabled /
    // setAlwaysExpanded).
    property bool overrideExists: false

    // User override / master file. When it loads it becomes the source of truth;
    // when it is absent (loadFailed) the shipped file takes over. printErrors is
    // off so a missing override does not log an error on every startup/reload.
    FileView {
        id: overrideFile
        // Every bar reads the file, but only the focused one writes it (via
        // IPC), so the others follow the change from disk.
        watchChanges: true
        onFileChanged: reload()
        path: Quickshell.env("HOME") + "/.config/quickshell/StatusbarApp/statusbar.json"
        blockLoading: true
        printErrors: false
        onLoaded: { root.overrideExists = true; root.applySettings() }
        onLoadFailed: { root.overrideExists = false; root.applySettings() }
    }

    // Shipped fallback holding the dynamic state (enabled / alwaysExpanded), used
    // only when the override file is absent. Changes on disk are picked up
    // automatically; "qs ipc call statusbar reload" forces a re-read.
    FileView {
        id: settingsFile
        // Every bar reads the file, but only the focused one writes it (via
        // IPC), so the others follow the change from disk.
        watchChanges: true
        onFileChanged: reload()
        path: Quickshell.env("HOME") + "/.config/ml4w/settings/statusbar.json"
        blockLoading: true
        onLoaded: root.applySettings()
    }

    // The active master file: the override when it exists, otherwise the shipped
    // file. The IPC setters write here and applySettings reads from here.
    function masterFile() {
        return root.overrideExists ? overrideFile : settingsFile
    }

    // Force a re-read of both settings files and re-apply them. reload()
    // refreshes each FileView from disk (re-firing onLoaded/onLoadFailed, which
    // re-runs applySettings with an up-to-date overrideExists).
    function reloadSettings(): void {
        overrideFile.reload()
        settingsFile.reload()
        applySettings()
    }

    // Parse a settings JSON document that may contain a /* ... */ comment block
    // and — being hand-edited — trailing commas before a closing } or ], which
    // strict JSON.parse rejects. Returns the parsed object, or undefined when the
    // text is empty or cannot be parsed even after that cleanup. Never throws.
    function parseSettings(src) {
        if (!src)
            return undefined
        let raw = src.replace(/\/\*[\s\S]*?\*\//g, "")
        if (raw.trim() === "")
            return undefined
        try {
            return JSON.parse(raw)
        } catch (e) {
            try {
                // Tolerate trailing commas: ",}" / ",]" (optional whitespace).
                return JSON.parse(raw.replace(/,(\s*[}\]])/g, "$1"))
            } catch (e2) {
                console.warn("statusbar settings: could not parse a file,"
                    + " ignoring it:", e2)
                return undefined
            }
        }
    }

    // Merge one JSON document (given as text) over an already-built settings
    // object, key by key. Empty or unparseable text is ignored so a
    // missing/partial file never clears previously merged values.
    function mergeSettings(merged, src): void {
        let parsed = parseSettings(src)
        if (parsed === undefined)
            return
        for (let group in parsed)
            for (let key in parsed[group])
                if (merged[group] !== undefined)
                    merged[group][key] = parsed[group][key]
    }

    // Rebuild the settings object: the built-in defaults with the master file
    // merged on top. An explicit masterText can be passed (e.g. right after a
    // switch writes the master file) so the merge does not depend on the FileView
    // buffer having refreshed yet.
    function applySettings(masterText): void {
        let merged = JSON.parse(JSON.stringify(root.defaultSettings))
        let text = (masterText !== undefined) ? masterText : root.masterFile().text()
        mergeSettings(merged, text)
        root.settings = merged
    }

    // Persist a <group>.<key> boolean into the master file and return the
    // updated text. A regex replace is used when the key is already present (so
    // file's formatting/comments are kept); when the key is missing (e.g. an
    // override file that did not list it) it falls back to a JSON rewrite of the
    // parsed document. If the file cannot be parsed at all the write is skipped
    // rather than replaced with an empty object, so a malformed hand-edited
    // override is never wiped — its current text is returned unchanged.
    //
    // Like persistString, the key is matched on its own rather than within its
    // group, so it has to be unique across the document.
    function persistFlag(group, key, on): string {
        let file = root.masterFile()
        let src = file.text()
        let re = new RegExp('("' + key + '"\\s*:\\s*)(true|false)')
        let updated
        if (re.test(src)) {
            updated = src.replace(re, "$1" + (on ? "true" : "false"))
        } else {
            let obj = root.parseSettings(src)
            if (obj === undefined && src && src.trim() !== "") {
                // Unparseable and non-empty: don't destroy the user's file.
                console.warn("statusbar settings: master file is not valid"
                    + " JSON; leaving it untouched instead of overwriting.")
                return src
            }
            if (typeof obj !== "object" || obj === null)
                obj = {}
            if (obj[group] === undefined)
                obj[group] = {}
            obj[group][key] = on
            updated = JSON.stringify(obj, null, 4) + "\n"
        }
        file.setText(updated)
        return updated
    }

    // Persist a string setting into the master file and return the updated text.
    // Mirrors persistFlag: a regex replace while the key is already there (so
    // the file's formatting and comments survive), a JSON rewrite of the parsed
    // document when it is not, and no write at all when the file is non-empty
    // and unparseable. The key is matched on its own, not within its group, so
    // it has to be unique across the document — "location" is.
    // Persist a number into the master file and return the updated text. Same
    // rules as persistString; the key has to be unique across the document.
    function persistNumber(group, key, value): string {
        let file = root.masterFile()
        let src = file.text()
        let re = new RegExp('("' + key + '"\\s*:\\s*)-?[0-9.]+')
        let updated
        if (re.test(src)) {
            updated = src.replace(re, (m, p1) => p1 + String(value))
        } else {
            let obj = root.parseSettings(src)
            if (obj === undefined && src && src.trim() !== "") {
                console.warn("statusbar settings: master file is not valid"
                    + " JSON; leaving it untouched instead of overwriting.")
                return src
            }
            if (typeof obj !== "object" || obj === null)
                obj = {}
            if (obj[group] === undefined)
                obj[group] = {}
            obj[group][key] = value
            updated = JSON.stringify(obj, null, 4) + "\n"
        }
        file.setText(updated)
        return updated
    }

    function persistString(group, key, value): string {
        let file = root.masterFile()
        let src = file.text()
        let escaped = String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
        let re = new RegExp('("' + key + '"\\s*:\\s*)"(?:[^"\\\\]|\\\\.)*"')
        let updated
        if (re.test(src)) {
            updated = src.replace(re, (m, p1) => p1 + '"' + escaped + '"')
        } else {
            let obj = root.parseSettings(src)
            if (obj === undefined && src && src.trim() !== "") {
                console.warn("statusbar settings: master file is not valid"
                    + " JSON; leaving it untouched instead of overwriting.")
                return src
            }
            if (typeof obj !== "object" || obj === null)
                obj = {}
            if (obj[group] === undefined)
                obj[group] = {}
            obj[group][key] = value
            updated = JSON.stringify(obj, null, 4) + "\n"
        }
        file.setText(updated)
        return updated
    }

    property int barHeight: settings.bar.height
    // Vertical space reserved for the bar. The bar sits flush against the top
    // edge, so this is simply the bar's own height: windows tile immediately
    // below it with no floating gap to pay for. Kept as a separate setting so
    // it can be padded independently if wanted.
    property int reservedHeight: Math.max(settings.bar.reservedHeight, settings.bar.height)

    // Whether the bar is shown. The "enabled" flag in statusbar.json is the
    // single source of truth; it is toggled via "qs ipc call statusbar toggle"
    // (SUPER + CTRL + B), persisted back to the file, and survives
    // restarts. Kept as a binding so a settings reload updates it for free.
    property bool barEnabled: settings.bar.enabled

    // Hide completely and reserve no space when disabled.
    visible: barEnabled
    // Windows tile directly under the bar. The pill only ever grows sideways,
    // so the reserved strip never has to account for an expanded state.
    exclusiveZone: barEnabled ? reservedHeight : 0

    // Persist the enabled state into the master file (override when present,
    // otherwise the shipped file) and apply it. applySettings re-parses the
    // updated text, which updates settings.bar.enabled and therefore the
    // barEnabled binding above.
    function setEnabled(on: bool): void {
        applySettings(persistFlag("bar", "enabled", on))
    }

    // Keep the pill expanded regardless of hover. Set via IPC
    // ("qs ipc call statusbar focus") which is bound to SUPER + SPACE in
    // Hyprland, and cleared on Escape, after running a module, or when the
    // focus grab is released because the user interacted with another window.
    property bool barExpanded: false

    // Set by shell.qml while the desktop widget is showing the time and date on
    // an empty workspace: the bar folds its own clock away so the two are never
    // both on screen. The handover timing lives in the widget.
    property bool hideClock: false

    // --- MULTI-MONITOR ---
    // shell.qml creates one bar per screen. The primary one shares its screen
    // with the desktop widget.
    property bool isPrimary: true
    // This bar's Hyprland monitor, used to show only its own workspaces.
    readonly property var hyprMonitor: Hyprland.monitorFor(root.screen)
    // Only the bar on the focused monitor answers IPC, so keybindings (panels,
    // SUPER + SPACE) act on the screen you are working on, and each target is
    // registered once rather than once per bar.
    readonly property bool ipcActive: Hyprland.focusedMonitor === Hyprland.monitorFor(root.screen)
    // What the handlers actually follow. Switching off is immediate, switching
    // on waits a tick, so when focus moves the old bar has always released a
    // target before the new one claims it. Otherwise the new one can register
    // first, and Quickshell logs a conflict for every target on every switch.
    property bool ipcEnabled: false
    onIpcActiveChanged: syncIpc()
    function syncIpc(): void {
        if (!root.ipcActive)
            root.ipcEnabled = false
        else
            Qt.callLater(() => root.ipcEnabled = root.ipcActive)
    }

    // When set in statusbar.json the pill never collapses: it stays in its
    // expanded (full-width) state independent of hover or the IPC toggle. This
    // is purely visual — unlike barExpanded it does not grab the keyboard — so
    // the left/right module areas remain permanently visible.
    property bool alwaysExpanded: settings.bar.alwaysExpanded

    // Persist the alwaysExpanded state into the master file and apply it.
    // Mirrors setEnabled.
    function setAlwaysExpanded(on: bool): void {
        applySettings(persistFlag("bar", "alwaysExpanded", on))
    }

    // Whether the desktop time/weather widget is allowed onto an empty
    // workspace. shell.qml hands this to the widget; with it off the widget
    // never appears and the bar keeps its own clock permanently.
    property bool weatherWidgetEnabled: settings.weather.desktopWidget

    // Persist the desktop widget flag into the master file and apply it.
    // Mirrors setEnabled.
    function setWeatherWidget(on: bool): void {
        applySettings(persistFlag("weather", "desktopWidget", on))
    }

    // --- MODULE PLACEMENT ---
    // Each module name in the settings file maps to the component placed into
    // the left/center/right groups. Unknown names load nothing.
    Component { id: cTerminal;   TerminalModule {} }
    Component {
        id: cWorkspaces
        WorkspacesModule {
            minWorkspaces: root.settings.workspaces.count
            showAppIcons: root.settings.workspaces.showAppIcons
            monitor: root.hyprMonitor
        }
    }
    Component {
        id: cLauncher
        LauncherModule {
            onClicked: root.togglePanel("launcher")
        }
    }
    Component {
        id: cClock
        ClockModule {
            expanded: pill.expanded
            hidden: root.hideClock
            timeFormat: root.settings.clock.format
            dateFormat: root.settings.clock.dateFormat
            // Rebuild the keyboard navigation list when the clock folds away or
            // comes back, the same way the other foldable modules do.
            onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
            onToggleRequested: root.togglePanel("calendar")
        }
    }
    // The clock's opposite number: it unfolds into the gap the clock leaves
    // while the desktop widget has the time, so the calendar is still one
    // click away from the middle of the bar.
    Component {
        id: cCalendar
        CalendarModule {
            shown: root.hideClock
            // Rebuild the keyboard navigation list as it folds in and out, the
            // same way the clock does.
            onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
            onClicked: root.togglePanel("calendar")
        }
    }
    Component {
        id: cMedia
        MediaModule {
            titleWidth: root.settings.media.titleWidth
            // Rebuild the keyboard navigation list when a player appears or
            // goes away (the module folds out of the layout with it).
            onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
            // A click on a panel that hovering opened keeps it open (and gives
            // it the keyboard) rather than closing it under the pointer.
            onClicked: {
                if (root.mediaHoverOpen)
                    root.mediaHoverOpen = false
                else
                    root.togglePanel("media")
            }
        }
    }

    // --- MEDIA PANEL ON HOVER ---
    // Resting the pointer on the media module for a second opens its panel, and
    // leaving both the module and the panel closes it again. The close waits a
    // moment so crossing from the module down into the panel (over the strip of
    // bar between them) never drops it. A panel opened by a click, a keybinding
    // or the keyboard is left alone.
    property bool mediaHoverOpen: false
    readonly property bool mediaHoverInside:
        (root.moduleRefs["media"] ? root.moduleRefs["media"].hovered === true : false)
        || mediaPanel.hovered

    onMediaHoverInsideChanged: {
        if (root.mediaHoverInside) {
            mediaHoverCloseTimer.stop()
            if (root.openPanel === "")
                mediaHoverOpenTimer.restart()
        } else {
            mediaHoverOpenTimer.stop()
            if (root.mediaHoverOpen)
                mediaHoverCloseTimer.restart()
        }
    }

    // Anything else taking over the panel slot ends hover mode, and takes the
    // notification list with it: the list belongs to the control centre.
    onOpenPanelChanged: {
        if (root.openPanel !== "media")
            root.mediaHoverOpen = false
        if (root.openPanel !== "controlcentre")
            root.notificationsOpen = false
    }

    Timer {
        id: mediaHoverOpenTimer
        interval: 400
        onTriggered: {
            if (root.mediaHoverInside && root.openPanel === "") {
                root.mediaHoverOpen = true
                root.openPanel = "media"
            }
        }
    }

    Timer {
        id: mediaHoverCloseTimer
        interval: 400
        onTriggered: {
            if (root.mediaHoverOpen && !root.mediaHoverInside)
                root.closePanel("media")
        }
    }
    Component {
        id: cControlCentre
        ControlCentreModule {
            onClicked: root.togglePanel("controlcentre")
            // Right click goes straight to the notifications, without the
            // control centre: the same list, dropped from the bar on its own.
            // Unaffected by Do Not Disturb — the list is where the collected
            // notifications are, which is exactly what is wanted while the
            // alert is off.
            onRightClicked: root.togglePanel("notifications")
        }
    }
    // True while a system-tray context menu is open. Kept at window scope so
    // the pill can pin itself expanded while a menu is up (the tray lives in
    // the right area, which only exists while expanded).
    property bool trayMenuOpen: false
    Component {
        id: cSystemTray
        SystemTrayModule {
            // Rebuild keyboard navigation when the tray empties or repopulates
            // (it collapses out of the layout when it has no items).
            onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
            // Surface the open-menu state up to the window so the pill stays
            // expanded for as long as a tray menu is showing.
            Binding {
                target: root
                property: "trayMenuOpen"
                value: menuOpen
            }
        }
    }
    Component {
        id: cNotificationTicker
        NotificationTickerModule {
            available: root.settings.notifications.tickerWidth
            // A notification that is not about a file asks for the list; one
            // that is opens that file's folder itself.
            onOpenRequested: root.togglePanel("notifications")
        }
    }
    Component { id: cKeyboard;   KeyboardLayoutModule {} }
    Component {
        id: cClipboard
        ClipboardModule {
            onClicked: root.togglePanel("clipboard")
        }
    }
    Component {
        id: cPower
        PowerModule {
            onClicked: root.togglePanel("power")
        }
    }
    Component {
        id: cVolume
        VolumeModule {
            onClicked: root.togglePanel("sound")
        }
    }
    Component {
        id: cUpdates
        UpdatesModule {
            // Rebuild the keyboard navigation list when the module hides or
            // reappears (its collapsed state tracks the available update count).
            onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
        }
    }
    Component {
        id: cBattery
        BatteryModule {
            // Rebuild the keyboard navigation list when the module hides or
            // reappears (it only shows while running on battery power).
            onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
        }
    }
    Component {
        id: cPowerProfile
        PowerProfileModule {
            panelFlare: pill.flare
            panelRadius: pill.bottomRadius
            panelOpacity: root.settings.opacity.expanded
            panelGap: Math.max(0, (root.barHeight - height) / 2)
            onRightClicked: root.togglePanel("system")
        }
    }

    readonly property var moduleComponents: ({
        "terminal":   cTerminal,
        "workspaces": cWorkspaces,
        "launcher":   cLauncher,
        "clock":      cClock,
        "calendar":   cCalendar,
        "controlcentre": cControlCentre,
        // The control centre was called "notifications" when it was only a
        // notification list. Kept as an alias so an existing statusbar.json
        // keeps working. (The panel of that name is the notification list that
        // drops from the middle of the bar; this is the module list, which is
        // a different namespace.)
        "notifications": cControlCentre,
        "media":         cMedia,
        // The newest waiting notification, beside the media slot. Its slot is
        // reserved exactly as the media slot is: see the module.
        "notificationticker": cNotificationTicker,
        "ticker":             cNotificationTicker,
        "systemtray": cSystemTray,
        "keyboard":   cKeyboard,
        "clipboard":  cClipboard,
        "power":      cPower,
        "updates":      cUpdates,
        "volume":       cVolume,
        "battery":      cBattery,
        "powerprofile": cPowerProfile
    })

    // --- DROPDOWN PANELS ---
    // Name of the panel currently hanging off the bar, "" for none. Only one is
    // ever open: opening a second closes the first.
    property string openPanel: ""

    function togglePanel(name: string): void {
        root.openPanel = (root.openPanel === name) ? "" : name
    }

    // --- THE CONTROL CENTRE AND ITS NOTIFICATION LIST ---
    // The notification list is the one panel that is not in the single panel
    // slot: it spawns sideways out of the control centre's right edge, from its
    // "Open" button, and the control centre stays exactly where it is. So it
    // has a flag of its own rather than a name in openPanel, and it only ever
    // lives as long as the control centre does.
    //
    // It is a free-standing card (shared/SideCard.qml), not a panel hanging off
    // the bar, so the bar neither widens for it nor has to cover it — which is
    // also why opening it costs nothing: nothing moves and nothing resizes
    // except the card's own width.
    property bool notificationsOpen: false

    // Where the card sits: pinned by its left edge *against* the control
    // centre's right edge, with no gap, so the two read as one body.
    readonly property real ccPanelWidth: 420
    readonly property real notificationsPanelWidth: 380

    // The row the card grows out of, in the control centre's coordinates. Read
    // from the panel itself so it follows the layout rather than a number kept
    // in two places; the fallback only matters before the panel exists.
    readonly property real ccNotificationsRowY: controlCentrePanel.content
        ? controlCentrePanel.content.notificationsRowY : 230

    // True while a panel is flush with the bar's right edge, so the bar can
    // merge its silhouette into it.
    readonly property bool rightEdgePanelOpen: root.openPanel === "power"

    function closePanel(name: string): void {
        if (root.openPanel === name)
            root.openPanel = ""
    }

    // How far the clock's rule sits off the centre group's own centre, which
    // is the centre of the screen. The group pads its left end by this, which
    // slides the rule back onto the centre line and leaves the slack outside
    // the group's first module instead of inside the clock in front of the
    // time. See the note in ClockModule.
    readonly property real clockInkSlack:
        root.moduleRefs["clock"] && root.moduleRefs["clock"].inkSlack !== undefined
            ? root.moduleRefs["clock"].inkSlack : 0

    // The loaded module instances by name, so a panel can hang off the icon
    // that owns it. Rebuilt alongside navItems, and replaced wholesale so the
    // anchor bindings below re-evaluate.
    property var moduleRefs: ({})

    // --- KEYBOARD NAVIGATION ---
    // Ordered left-to-right list of the navigable items, rebuilt from the
    // placed modules whenever the layout or the (dynamic) workspace buttons
    // change. The workspace buttons are spliced in at the workspaces module's
    // position; collection modules without a single action (the system tray)
    // are skipped.
    property var navItems: []
    // Index of the keyboard-selected item, or -1 when none is selected.
    property int focusIndex: -1

    // The placed workspaces module, tracked so navItems can be rebuilt when its
    // button list changes (workspaces appear/disappear asynchronously).
    property var workspacesRef: null
    Connections {
        target: root.workspacesRef
        ignoreUnknownSignals: true
        function onNavButtonsChanged(): void { root.rebuildNavItems() }
    }

    function rebuildNavItems(): void {
        let items = []
        let ws = null
        let refs = ({})
        let groups = [
            [leftRepeater,   root.settings.modules.left],
            [centerRepeater, root.settings.modules.center],
            [rightRepeater,  root.settings.modules.right]
        ]
        for (let g = 0; g < groups.length; g++) {
            let rep = groups[g][0]
            let names = groups[g][1]
            for (let i = 0; i < rep.count; i++) {
                let loader = rep.itemAt(i)
                let m = loader ? loader.item : null
                if (!m)
                    continue
                // Record every placed module, hidden ones included: a panel
                // still needs somewhere to hang from.
                if (names && names[i] !== undefined)
                    refs[names[i]] = m
                if (m.collapsed === true)                // hidden (e.g. updates)
                    continue
                if (m.navButtons !== undefined) {        // workspaces
                    ws = m
                    items = items.concat(m.navButtons)
                } else if (typeof m.activate === "function") {
                    items.push(m)
                }
            }
        }
        root.workspacesRef = ws
        root.navItems = items
        root.moduleRefs = refs
    }

    Component.onCompleted: {
        Qt.callLater(rebuildNavItems)
        syncIpc()
    }
    onSettingsChanged: Qt.callLater(rebuildNavItems)

    // Highlight exactly the item at focusIndex and clear all others. Called
    // both when the selection moves and when navItems changes underneath it.
    function applyFocus(): void {
        let items = root.navItems
        for (let i = 0; i < items.length; i++)
            items[i].focused = (i === root.focusIndex)
    }

    onFocusIndexChanged: applyFocus()
    onNavItemsChanged: {
        // Keep the selection in range when the workspace count changes.
        if (root.focusIndex >= root.navItems.length)
            root.focusIndex = root.navItems.length - 1
        applyFocus()
    }

    onBarExpandedChanged: {
        if (barExpanded) {
            focusIndex = 0
            keyHandler.forceActiveFocus()
        } else {
            focusIndex = -1
        }
    }

    function moveFocus(dir: int): void {
        if (!barExpanded)
            return
        let n = root.navItems.length
        root.focusIndex = (root.focusIndex + dir + n) % n
    }

    // Forward an Up/Down press to the keyboard-selected module if it exposes a
    // step() function (e.g. the volume module), so the arrows adjust it in place
    // without leaving keyboard-navigation mode.
    function stepFocused(dir: int): void {
        if (root.focusIndex < 0 || root.focusIndex >= root.navItems.length)
            return
        let m = root.navItems[root.focusIndex]
        if (typeof m.step === "function")
            m.step(dir)
    }

    function activateFocused(): void {
        if (root.focusIndex >= 0 && root.focusIndex < root.navItems.length)
            root.navItems[root.focusIndex].activate()
        // Collapse so the keyboard is handed back to the (possibly newly
        // launched) application instead of staying captured by the bar.
        root.barExpanded = false
    }

    // The calendar and power menu used to be windows of their own, each with
    // its own IPC target. They are panels of the bar now, but the targets are
    // kept exactly as they were so existing keybindings and scripts keep
    // working.
    IpcHandler {
        enabled: root.ipcEnabled
        target: "calendar"
        function toggle(): void { root.togglePanel("calendar") }
        function open(): void { root.openPanel = "calendar" }
        function close(): void { root.closePanel("calendar") }
        function isOpen(): bool { return root.openPanel === "calendar" }
    }

    IpcHandler {
        enabled: root.ipcEnabled
        target: "power"
        function toggle(): void { root.togglePanel("power") }
        function open(): void { root.openPanel = "power" }
        function close(): void { root.closePanel("power") }
        function isOpen(): bool { return root.openPanel === "power" }
    }

    IpcHandler {
        enabled: root.ipcEnabled
        target: "wallpaper"
        function toggle(): void { root.togglePanel("wallpaper") }
        function open(): void { root.openPanel = "wallpaper" }
        function close(): void { root.closePanel("wallpaper") }
        function isOpen(): bool { return root.openPanel === "wallpaper" }
    }

    IpcHandler {
        enabled: root.ipcEnabled
        target: "media"
        function toggle(): void { root.togglePanel("media") }
        function open(): void { root.openPanel = "media" }
        function close(): void { root.closePanel("media") }
        function isOpen(): bool { return root.openPanel === "media" }
    }

    IpcHandler {
        enabled: root.ipcEnabled
        target: "controlcentre"
        function toggle(): void { root.togglePanel("controlcentre") }
        function open(): void { root.openPanel = "controlcentre" }
        function close(): void { root.closePanel("controlcentre") }
        function isOpen(): bool { return root.openPanel === "controlcentre" }
    }

    // The notification list on its own, dropping from the middle of the bar
    // with no control centre behind it. This target used to be an alias for the
    // control centre, from when the control centre was the only way to reach
    // the notifications; nothing called it, and the name belongs to the list.
    IpcHandler {
        enabled: root.ipcEnabled
        target: "notifications"
        function toggle(): void { root.togglePanel("notifications") }
        function open(): void { root.openPanel = "notifications" }
        function close(): void { root.closePanel("notifications") }
        function isOpen(): bool { return root.openPanel === "notifications" }
    }

    // The notification list beside the control centre. It opens the pair, so
    // the control centre comes out with it.
    IpcHandler {
        enabled: root.ipcEnabled
        target: "notificationlist"
        function toggle(): void {
            if (root.notificationsOpen) {
                root.notificationsOpen = false
            } else {
                root.openPanel = "controlcentre"
                root.notificationsOpen = true
            }
        }
        function open(): void {
            root.openPanel = "controlcentre"
            root.notificationsOpen = true
        }
        function close(): void { root.notificationsOpen = false }
        function isOpen(): bool { return root.notificationsOpen }
    }

    // The system panel. For now it opens with a right click on the power
    // profile icon; this is what a keybinding will call.
    IpcHandler {
        enabled: root.ipcEnabled
        target: "system"
        function toggle(): void { root.togglePanel("system") }
        function open(): void { root.openPanel = "system" }
        function close(): void { root.closePanel("system") }
        function isOpen(): bool { return root.openPanel === "system" }
    }

    IpcHandler {
        enabled: root.ipcEnabled
        target: "sound"
        function toggle(): void { root.togglePanel("sound") }
        function open(): void { root.openPanel = "sound" }
        function close(): void { root.closePanel("sound") }
        function isOpen(): bool { return root.openPanel === "sound" }
    }

    IpcHandler {
        enabled: root.ipcEnabled
        target: "clipboard"
        function toggle(): void { root.togglePanel("clipboard") }
        function open(): void { root.openPanel = "clipboard" }
        function close(): void { root.closePanel("clipboard") }
        function isOpen(): bool { return root.openPanel === "clipboard" }
    }

    // The sidebar was merged into the control centre. Its target is kept as an
    // alias so old keybindings, aliases and scripts land in the right place.
    IpcHandler {
        enabled: root.ipcEnabled
        target: "sidebar"
        function toggle(): void { root.togglePanel("controlcentre") }
        function open(): void { root.openPanel = "controlcentre" }
        function close(): void { root.closePanel("controlcentre") }
        function isOpen(): bool { return root.openPanel === "controlcentre" }
    }

    IpcHandler {
        enabled: root.ipcEnabled
        target: "launcher"
        function toggle(): void { root.togglePanel("launcher") }
        function open(): void { root.openPanel = "launcher" }
        function close(): void { root.closePanel("launcher") }
        function isOpen(): bool { return root.openPanel === "launcher" }
    }

    // The keybinding cheat sheet (SUPER + CTRL + K). It replaced
    // scripts/keybindings.sh, which showed the same list in rofi.
    IpcHandler {
        enabled: root.ipcEnabled
        target: "keybinds"
        function toggle(): void { root.togglePanel("keybinds") }
        function open(): void { root.openPanel = "keybinds" }
        function close(): void { root.closePanel("keybinds") }
        function isOpen(): bool { return root.openPanel === "keybinds" }
    }

    // The OCR language picker (SUPER + ALT + A). It replaced the rofi menu
    // inside scripts/text-extractor.sh; picking a language in the panel is
    // what starts the capture.
    IpcHandler {
        enabled: root.ipcEnabled
        target: "ocr"
        function toggle(): void { root.togglePanel("ocr") }
        function open(): void { root.openPanel = "ocr" }
        function close(): void { root.closePanel("ocr") }
        function isOpen(): bool { return root.openPanel === "ocr" }
    }

    IpcHandler {
        enabled: root.ipcEnabled
        target: "settings"
        function toggle(): void { root.togglePanel("settings") }
        function open(): void { root.openPanel = "settings" }
        function close(): void { root.closePanel("settings") }
        function isOpen(): bool { return root.openPanel === "settings" }
    }

    IpcHandler {
        enabled: root.ipcEnabled
        target: "statusbar"
        function toggle(): void { root.setEnabled(!root.settings.bar.enabled) }
        // Named enable/disable rather than show/hide: "show" is a reserved
        // subcommand of "qs ipc" and would never reach the function.
        function enable(): void { root.setEnabled(true) }
        function disable(): void { root.setEnabled(false) }
        // Persist and apply the alwaysExpanded (permanently expanded) mode.
        function alwaysExpand(): void { root.setAlwaysExpanded(true) }
        function autoCollapse(): void { root.setAlwaysExpanded(false) }
        // Re-read statusbar.json from disk.
        function refresh(): void { root.reloadSettings() }
        // Expand the bar (if needed) and grab the keyboard for navigation.
        // Bound to SUPER + SPACE. Idempotent: when the bar is already expanded
        // it only re-grabs keyboard focus instead of toggling back to collapsed,
        // so the keybinding always lands in keyboard-navigation mode.
        function focus(): void {
            root.barExpanded = true
            keyHandler.forceActiveFocus()
        }
        // Toggle between collapsed and expanded mode.
        function expand(): void { root.barExpanded = !root.barExpanded }
        function collapse(): void { root.barExpanded = false }
        // Re-read statusbar.json and apply the changes.
        function reload(): void { root.reloadSettings() }
        // The place the weather widgets look up. The bar owns the write, so the
        // settings panel and the notification centre both go through here
        // instead of editing statusbar.json themselves.
        function weatherLocation(): string { return root.settings.weather.location }
        // The desktop time/weather widget. Off means it never appears and the
        // bar's own clock stays out permanently. Toggled on the control
        // centre's Appearance page; the read returns "1" / "0" for a shell caller.
        function weatherWidget(): string {
            return root.weatherWidgetEnabled ? "1" : "0"
        }
        function enableWeatherWidget(): void { root.setWeatherWidget(true) }
        function disableWeatherWidget(): void { root.setWeatherWidget(false) }
        function toggleWeatherWidget(): void {
            root.setWeatherWidget(!root.weatherWidgetEnabled)
        }
        function setWeatherLocation(location: string): void {
            let name = location.trim()
            if (name === "")
                return
            root.applySettings(root.persistString("weather", "location", name))
        }
        // How long the notification card takes to grow out of the control
        // centre and to be sucked back in, in milliseconds.
        function notificationSpawn(): string {
            return String(root.settings.notifications.spawnDuration)
        }
        function setNotificationSpawn(ms: string): void {
            let v = parseInt(ms)
            if (isNaN(v))
                return
            v = Math.max(0, Math.min(2000, v))
            root.applySettings(root.persistNumber("notifications", "spawnDuration", v))
        }
        // Size of the desktop widget, 1.0 being the original size.
        function weatherWidgetScale(): string { return String(root.settings.weather.widgetScale) }
        function setWeatherWidgetScale(scale: string): void {
            let v = parseFloat(scale)
            if (isNaN(v))
                return
            v = Math.max(0.5, Math.min(1.5, v))
            root.applySettings(root.persistNumber("weather", "widgetScale", v))
        }
        // How long (ms) a workspace must stay empty before the widget returns.
        function weatherShowDelay(): string { return String(root.settings.weather.showDelay) }
        function setWeatherShowDelay(ms: string): void {
            let v = parseInt(ms)
            if (isNaN(v))
                return
            v = Math.max(0, Math.min(10000, v))
            root.applySettings(root.persistNumber("weather", "showDelay", v))
        }
    }

    color: "transparent"

    // Full-width strip anchored to the top of the screen
    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: 0
    }

    // The bar itself plus a little room underneath for its drop shadow.
    implicitHeight: barHeight + 24

    // ==========================================
    // CENTERED PILL
    // ==========================================
    Item {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        // Flush with the top of the screen: the bar is part of the edge rather
        // than a slab floating below it. Only its bottom corners are rounded,
        // which is what makes the screen edge run smoothly into the bar.
        anchors.top: parent.top

        // Collapsed = sized to content, Expanded = fixed width.
        // A panel hangs off one of the modules, so the bar must not collapse
        // out from under it while one is open.
        property bool expanded: hoverHandler.hovered || root.barExpanded
            || root.alwaysExpanded || root.trayMenuOpen || root.openPanel !== ""
        // 0 in the settings file means "hug the center content".
        // The center area carries half of its own gap on each outer end (see
        // its margins below), so 14 of the old padding is already in its
        // implicit width.
        property real collapsedWidth: root.settings.pill.collapsedWidth > 0
            ? root.settings.pill.collapsedWidth
            : centerArea.implicitWidth + 18

        // Minimum width the content needs so the centered center area never
        // overlaps the left/right areas. The center stays centered, so each
        // side must clear half of it: the bar has to be at least as wide as the
        // center plus twice the wider of the two side areas (whichever side
        // would collide first), plus the 16px edge margins and some breathing
        // room. Computed live so adding workspaces (or any module growing)
        // pushes the bar wider instead of clipping.
        property real contentWidth: centerArea.implicitWidth
            + 2 * Math.max(leftArea.implicitWidth, rightArea.implicitWidth)
            + 50
        // expandedWidth from the settings file is treated as a MINIMUM, not a
        // width: the pill grows past it whenever the content needs more room,
        // which on a full bar it always does. Setting it smaller therefore does
        // nothing at all, and setting it larger only pads a bar that is not yet
        // full. The width of a full bar is the width of its modules, and the
        // two that are adjustable are `media.titleWidth` and
        // `notifications.tickerWidth`.
        //
        // The bar is symmetric because the centre group has to sit on the
        // centre of the screen, so each half reserves the *wider* of the two
        // end groups. Whichever group is narrower therefore floats to its end
        // of the bar with the difference left as empty bar beside the centre
        // group. Trimming the two left-hand slots until the left group matches
        // the right is what closes that gap — nothing else in the bar can.
        property real expandedWidth: Math.max(
            root.settings.pill.expandedWidth, contentWidth)

        width: expanded ? expandedWidth : collapsedWidth
        // Constant height: expanding grows the bar sideways only, so it never
        // eats more vertical space and the modules never shift up or down.
        height: root.barHeight

        // Convex rounding of the two bottom corners, and the sideways reach of
        // the concave flares at the top. Together they must not exceed the
        // bar's height, or the two curves would meet and fold over each other.
        property real bottomRadius: Math.min(root.settings.pill.radius,
            root.barHeight / 2)
        property real flare: Math.min(root.settings.pill.flareRadius,
            root.barHeight - bottomRadius)

        // How far the first and last module sit from the bar's ends. The two
        // ends are entirely curve — the flare arc runs straight into the bottom
        // corner — so a module parked at a flat 16 sits visibly tighter against
        // that curve than the same gap looks anywhere else. Scaled off the
        // flare so the breathing room holds if the silhouette is retuned.
        property real edgeMargin: Math.max(16, pill.flare + 6)

        Behavior on width {
            NumberAnimation {
                duration: root.settings.pill.animationDuration
                easing.type: Easing.OutQuint
            }
        }

        HoverHandler {
            id: hoverHandler
        }

        // Captures arrow keys (navigate), Return (execute) and Escape
        // (collapse) while the bar is in expanded mode.
        FocusScope {
            id: keyHandler
            anchors.fill: parent
            focus: root.barExpanded
            Keys.onLeftPressed: root.moveFocus(-1)
            Keys.onRightPressed: root.moveFocus(1)
            Keys.onUpPressed: root.stepFocused(1)
            Keys.onDownPressed: root.stepFocused(-1)
            Keys.onReturnPressed: root.activateFocused()
            Keys.onEnterPressed: root.activateFocused()
            Keys.onEscapePressed: root.barExpanded = false
        }

        // ==========================================
        // BAR BACKGROUND
        // ==========================================
        // The bar's silhouette lives in shared/BarShape.qml, because every
        // panel that drops out of the bar draws itself with exactly the same
        // path — that is what makes a panel read as the bar continuing
        // downwards rather than as a separate card sitting under it.
        //
        //   flareRadius: how far each end reaches sideways along the top edge.
        //   radius:      the convex rounding of the two bottom corners.
        BarShape {
            id: pillBg
            // The flares extend past the bar body on both sides.
            x: -pillBg.wingLeft
            y: 0

            bodyWidth: pill.width
            bodyHeight: pill.height
            flare: pill.flare
            cornerRadius: pill.bottomRadius
            // A panel pinned to the bar's right edge continues that edge
            // downwards, so the corner between them has to go. Animated, so the
            // bar squares off as the panel drops and rounds again as it leaves.
            radiusBottomRight: root.rightEdgePanelOpen ? 0 : pill.bottomRadius
            Behavior on radiusBottomRight {
                NumberAnimation { duration: 180; easing.type: Easing.OutQuint }
            }

            fillColor: Theme.background
            // The optional outline, off by default (border.width 0).
            strokeWidth: root.settings.border.width > 0
                ? root.settings.border.width : -1
            strokeColor: root.settings.border.colorTop !== ""
                ? root.settings.border.colorTop
                : Theme.primary

            opacity: pill.expanded
                ? root.settings.opacity.expanded
                : root.settings.opacity.collapsed
            Behavior on opacity {
                NumberAnimation {
                    duration: root.settings.pill.animationDuration
                    easing.type: Easing.OutQuint
                }
            }
        }

        // ==========================================
        // LEFT AREA (only visible when expanded)
        // ==========================================
        // The gap between the left modules is carried as a margin on each
        // module rather than as the layout's spacing, so a module can ask for
        // less of it. The round icon buttons want the full gap between their
        // hover circles; the media and notification slots are wide pills whose
        // ink starts 10px inside their own edge, so the full gap on top of that
        // reads as half again as much space as the buttons have between them.
        // They ask for `gapBefore: 0` and sit against their neighbour's gap
        // alone.
        RowLayout {
            id: leftArea
            anchors.left: parent.left
            anchors.leftMargin: pill.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            opacity: pill.expanded ? 1 : 0
            visible: opacity > 0
            enabled: pill.expanded

            Behavior on opacity {
                NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
            }

            Repeater {
                id: leftRepeater
                model: root.settings.modules.left
                Loader {
                    id: leftSlot
                    Layout.alignment: Qt.AlignVCenter
                    // Half the gap on each side, as in the centre group. A
                    // module may ask for less in front of it (gapBefore).
                    readonly property real gapBefore:
                        (item && item.gapBefore !== undefined) ? item.gapBefore : 7
                    // The first module sits on the bar's own edge margin,
                    // with no gap in front of it.
                    Layout.leftMargin: index === 0 ? 0 : leftSlot.gapBefore
                    Layout.rightMargin: 7
                    sourceComponent: root.moduleComponents[modelData] || null
                    onLoaded: Qt.callLater(root.rebuildNavItems)
                }
            }
        }

        // ==========================================
        // CENTER AREA (always visible)
        // ==========================================
        // The gap between the center modules is carried as a margin on each
        // module rather than as the layout's spacing, because a module that
        // folds away (the clock, when the desktop widget has the time) can then
        // close its own gap as it goes. Layout spacing would survive the fold
        // at full width and leave a hole in the middle of the bar.
        RowLayout {
            id: centerArea
            anchors.centerIn: parent
            spacing: 0

            // The slack, at whichever end of the group needs it. Invisible: it
            // is bar, with the left group's last module somewhere to its left.
            Item {
                Layout.preferredWidth: Math.max(0, root.clockInkSlack)
                Layout.preferredHeight: 1
            }

            Repeater {
                id: centerRepeater
                model: root.settings.modules.center
                Loader {
                    id: centerSlot
                    Layout.alignment: Qt.AlignVCenter
                    // Half the gap on each side, scaled down by however far the
                    // module has folded (0 = fully out, 1 = fully folded).
                    readonly property real foldAmount:
                        (item && item.fold !== undefined) ? item.fold : 0
                    Layout.leftMargin: 7 * (1 - centerSlot.foldAmount)
                    Layout.rightMargin: 7 * (1 - centerSlot.foldAmount)
                    sourceComponent: root.moduleComponents[modelData] || null
                    onLoaded: Qt.callLater(root.rebuildNavItems)
                }
            }

            Item {
                Layout.preferredWidth: Math.max(0, -root.clockInkSlack)
                Layout.preferredHeight: 1
            }
        }

        // ==========================================
        // RIGHT AREA (only visible when expanded)
        // ==========================================
        RowLayout {
            id: rightArea
            anchors.right: parent.right
            anchors.rightMargin: pill.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            opacity: pill.expanded ? 1 : 0
            visible: opacity > 0
            enabled: pill.expanded

            Behavior on opacity {
                NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
            }

            Repeater {
                id: rightRepeater
                model: root.settings.modules.right
                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: root.moduleComponents[modelData] || null
                    // Collapse the layout slot when the module marks itself
                    // collapsed (e.g. the updates module with no pending
                    // updates). Reading the plain `collapsed` flag — rather than
                    // the module's effective `visible` — avoids a binding latch
                    // that would pin this Loader hidden once the right area
                    // collapses in the pill's collapsed state.
                    visible: (item && item.collapsed !== undefined) ? !item.collapsed : true
                    onLoaded: Qt.callLater(root.rebuildNavItems)
                }
            }
        }

        // ==========================================
        // DROPDOWN PANELS
        // ==========================================
        // Each panel is an xdg popup anchored to the module that owns it, so it
        // tracks that icon on its own as the bar expands, contracts or gains a
        // module — nothing here computes a position. The panels draw nothing in
        // the bar itself; they are placed inside the pill only so their anchors
        // resolve against it.

        // Geometry every panel inherits from the bar, so a panel is drawn with
        // the same silhouette, flare and translucency as the bar itself.
        component BarDropdown: BarPanel {
            flare: pill.flare
            cornerRadius: pill.bottomRadius
            backgroundOpacity: root.settings.opacity.expanded
            // A panel hanging off a module hangs off that module's *bottom*,
            // which is a few pixels above the bar's: the modules are 30px tall
            // and centred in a taller bar. Left at zero the panel's top edge
            // would start inside the bar and its flares would curl against the
            // bar's fill instead of out of its underside. Panels anchored to
            // the bar body itself already start in the right place.
            gap: (anchorItem && anchorItem !== pill)
                ? Math.max(0, (pill.height - anchorItem.height) / 2)
                : 0
        }

        // --- WHERE THE NOTIFICATION CARD SPAWNS FROM ---
        // An invisible item whose *right edge* is where the notification card
        // begins: the control centre's right edge plus the gap. The card is
        // pinned to that edge and grows rightwards (SideCard's default edges),
        // so this is only ever read, never animated — the card's own width is
        // the whole animation, and the surface underneath never moves.
        //
        // Pinned at x = 0 and sized by width rather than placed by x, because
        // width is the half of an anchor that a mapped popup actually follows:
        // BarPanel and SideCard bind anchor.rect.width, but nothing re-reads an
        // anchor's position. It is as tall as the bar so the card starts from
        // the bar's underside, and draws nothing itself.
        Item {
            id: notificationsAnchor
            x: 0
            y: 0
            height: pill.height
            // The control centre is centred on the bar, so its right edge is
            // half the bar plus half the panel along.
            width: pill.width / 2 + root.ccPanelWidth / 2
        }

        BarDropdown {
            id: calendarPanel
            // Hangs off whichever of the two centre modules is currently out:
            // the clock normally, and the calendar button that replaces it
            // while the desktop widget has the time. Falls back to the bar
            // itself if neither is placed, so the keybinding still puts the
            // calendar somewhere sane.
            anchorItem: (root.hideClock ? root.moduleRefs["calendar"] : null)
                || root.moduleRefs["clock"] || root.moduleRefs["calendar"] || pill
            open: root.openPanel === "calendar"
            onDismissed: root.closePanel("calendar")
            panelWidth: 340
            panelHeight: 340
            panelContent: Component { CalendarPanel {} }
        }

        // The power menu hangs off the bar itself rather than off a module:
        // pinned to the bar's right edge and growing leftwards, with its right
        // flare dropped so that edge runs straight on from the bar's.
        BarDropdown {
            id: wallpaperPanel
            // Opened by a keybinding and from the control centre, with no icon
            // of its own, so it drops from the middle of the bar.
            anchorItem: pill
            open: root.openPanel === "wallpaper"
            onDismissed: root.closePanel("wallpaper")
            panelWidth: 420
            // Reaches down to roughly 80% of the screen: it is a browsing grid,
            // so the extra rows are worth more here than they are in the other
            // panels. Still leaves room below for the drop's overshoot.
            panelHeight: Math.max(320,
                Math.round(root.screen.height * 0.8) - root.barHeight)
            panelContent: Component {
                WallpaperPanel {
                    isOpen: root.openPanel === "wallpaper"
                    onCloseRequested: root.closePanel("wallpaper")
                }
            }
        }

        BarDropdown {
            id: mediaPanel
            anchorItem: root.moduleRefs["media"] || pill
            open: root.openPanel === "media"
            grabFocus: !root.mediaHoverOpen
            onDismissed: root.closePanel("media")
            panelWidth: 360
            panelHeight: 140
            panelContent: Component {
                MediaPanel {
                    isOpen: root.openPanel === "media"
                    onCloseRequested: root.closePanel("media")
                }
            }
        }

        BarDropdown {
            id: controlCentrePanel
            // Dropped from the middle of the bar, like the other wide panels.
            // It stays there while the notification card is out: the card
            // spawns beside it rather than pushing it over.
            anchorItem: pill
            open: root.openPanel === "controlcentre"
            onDismissed: root.closePanel("controlcentre")
            panelWidth: root.ccPanelWidth
            // Everything on one page, no scrolling: as tall as the content says
            // it needs, capped for short screens.
            panelHeight: Math.min(content ? content.panelHeight : 748,
                                  root.screen.height - root.barHeight - 72)
            // This panel holds the focus grab for the pair, so a click in the
            // card beside it is not a click outside. The card takes no grab.
            grabAlso: root.notificationsOpen ? [notificationsCard.grabWindow] : []
            panelContent: Component {
                ControlCentrePanel {
                    isOpen: root.openPanel === "controlcentre"
                    location: root.settings.weather.location
                    weatherWidgetEnabled: root.weatherWidgetEnabled
                    onCloseRequested: root.closePanel("controlcentre")
                    onSoundRequested: root.openPanel = "sound"
                    onNotificationsRequested:
                        root.notificationsOpen = !root.notificationsOpen
                }
            }
        }

        // The notification list. It spawns out of the control centre's right
        // edge and is sucked back into it on closing, so the toggles and the
        // levels never move and stay reachable to the left of it.
        SideCard {
            id: notificationsCard
            anchorItem: notificationsAnchor
            open: root.notificationsOpen
            onDismissed: root.notificationsOpen = false
            // The control centre's grab covers this card; a second grab here
            // would fight it for the pointer.
            grabFocus: false
            cardWidth: root.notificationsPanelWidth
            // Top level with the NOTIFICATIONS row it comes out of, bottom
            // stopping short of the control centre's rounded bottom corner so
            // the two straight edges meet along the card's whole height.
            topInset: root.ccNotificationsRowY
            cardHeight: controlCentrePanel.panelHeight
                - root.ccNotificationsRowY - pill.bottomRadius
            // Starts as a nub the height of that row.
            minHeight: 34
            cornerRadius: pill.bottomRadius
            // Stands clear of the control centre, joined to it only by the
            // stem at its top left, which flares into the control centre's edge
            // the way the bar flares into the top of the screen — and into the
            // card's own edge at the rule under its header, so the joint has no
            // square corner at either end.
            attachGap: 18
            attachCardY: notificationsCard.content
                ? notificationsCard.content.dividerY : 52
            backgroundOpacity: root.settings.opacity.expanded
            revealDuration: root.settings.notifications.spawnDuration
            cardContent: Component {
                NotificationPanel {
                    isOpen: root.notificationsOpen
                    onCloseRequested: root.notificationsOpen = false
                }
            }
        }

        BarDropdown {
            id: clipboardPanel
            // Dropped from the middle of the bar rather than from its icon:
            // it is a wide panel, and both its flares then land on the bar's
            // flat underside.
            anchorItem: pill
            open: root.openPanel === "clipboard"
            onDismissed: root.closePanel("clipboard")
            panelWidth: 400
            panelHeight: 440
            panelContent: Component {
                ClipboardPanel {
                    isOpen: root.openPanel === "clipboard"
                    onCloseRequested: root.closePanel("clipboard")
                }
            }
        }

        BarDropdown {
            id: powerPanel
            // Anchored to the bar body (not to pillBg, which includes the top
            // flares) so the panel's right edge sits exactly on the bar's right
            // side and the two read as one edge running down.
            anchorItem: pill
            anchorEdges: Edges.Bottom | Edges.Right
            anchorGravity: Edges.Bottom | Edges.Left
            flareRight: 0
            open: root.openPanel === "power"
            onDismissed: root.closePanel("power")
            // 5 buttons of 46 with 14 between them, inside the bar's own edge
            // margin — so the last button lands directly under the power icon.
            panelWidth: 5 * 46 + 4 * 14 + 2 * pill.edgeMargin
            panelHeight: 46 + 2 * 16
            panelContent: Component {
                PowerPanel {
                    padding: pill.edgeMargin
                    onActionTaken: root.closePanel("power")
                }
            }
        }

        BarDropdown {
            id: soundPanel
            // Opened from the bar's speaker and from the control centre's, so
            // it drops from the middle of the bar like the control centre it
            // is reached from.
            anchorItem: pill
            open: root.openPanel === "sound"
            onDismissed: root.closePanel("sound")
            panelWidth: 420
            panelHeight: Math.min(620, root.screen.height - root.barHeight - 72)
            panelContent: Component {
                SoundPanel {
                    isOpen: root.openPanel === "sound"
                    onCloseRequested: root.closePanel("sound")
                }
            }
        }

        BarDropdown {
            id: systemPanel
            // A wide panel, so it drops from the middle of the bar like the
            // control centre, whatever opened it.
            anchorItem: pill
            open: root.openPanel === "system"
            onDismissed: root.closePanel("system")
            panelWidth: 720
            // As tall as its content, capped for short screens.
            panelHeight: Math.min(content ? content.panelHeight : 800,
                                  root.screen.height - root.barHeight - 72)
            panelContent: Component {
                SystemPanel {
                    isOpen: root.openPanel === "system"
                    onCloseRequested: root.closePanel("system")
                }
            }
        }

        BarDropdown {
            id: launcherPanel
            // A wide panel, so it drops from the middle of the bar like the
            // control centre, whether opened from its icon or by IPC.
            anchorItem: pill
            open: root.openPanel === "launcher"
            onDismissed: root.closePanel("launcher")
            panelWidth: 520
            panelHeight: Math.min(520, root.screen.height - root.barHeight - 72)
            panelContent: Component {
                LauncherPanel {
                    isOpen: root.openPanel === "launcher"
                    onCloseRequested: root.closePanel("launcher")
                }
            }
        }

        BarDropdown {
            id: keybindsPanel
            // A wide panel with no icon of its own, so it drops from the
            // middle of the bar like the control centre.
            anchorItem: pill
            open: root.openPanel === "keybinds"
            onDismissed: root.closePanel("keybinds")
            panelWidth: 560
            panelHeight: Math.min(560, root.screen.height - root.barHeight - 72)
            panelContent: Component {
                KeybindsPanel {
                    isOpen: root.openPanel === "keybinds"
                    onCloseRequested: root.closePanel("keybinds")
                }
            }
        }

        // The notification list on its own, with no control centre behind it:
        // the same content as the card that grows out of the control centre,
        // hosted by a plain bar dropdown instead. Reached by a right click on
        // the control centre icon, by SUPER + CTRL + N and over IPC.
        //
        // Only one of the two is ever up, because this one is an openPanel name
        // and the card is cleared whenever openPanel leaves "controlcentre".
        BarDropdown {
            id: notificationsPanel
            // Opened by a keybinding and by right-clicking an icon that is in
            // the centre group, so it drops from the middle of the bar like the
            // wallpaper and OCR panels rather than from that icon: the list is
            // not a menu belonging to the control centre's button.
            anchorItem: pill
            open: root.openPanel === "notifications"
            onDismissed: root.closePanel("notifications")
            panelWidth: root.notificationsPanelWidth
            panelHeight: Math.min(520,
                root.screen.height - root.barHeight - 72)
            panelContent: Component {
                NotificationPanel {
                    isOpen: root.openPanel === "notifications"
                    onCloseRequested: root.closePanel("notifications")
                }
            }
        }

        BarDropdown {
            id: ocrPanel
            // Opened by a keybinding only, so it drops from the middle of the
            // bar. Short: as tall as the list of installed languages.
            anchorItem: pill
            open: root.openPanel === "ocr"
            onDismissed: root.closePanel("ocr")
            panelWidth: 300
            panelHeight: Math.min(content ? content.panelHeight : 200,
                                  root.screen.height - root.barHeight - 72)
            panelContent: Component {
                OcrPanel {
                    isOpen: root.openPanel === "ocr"
                    onCloseRequested: root.closePanel("ocr")
                }
            }
        }

        BarDropdown {
            id: settingsPanel
            // Opened from the control centre and by IPC, with no icon of its own, so it
            // drops from the middle of the bar like the other wide panels.
            anchorItem: pill
            open: root.openPanel === "settings"
            onDismissed: root.closePanel("settings")
            panelWidth: 440
            panelHeight: Math.min(640, root.screen.height - root.barHeight - 72)
            panelContent: Component {
                SettingsPanel {
                    isOpen: root.openPanel === "settings"
                    onCloseRequested: root.closePanel("settings")
                }
            }
        }
    }
}
