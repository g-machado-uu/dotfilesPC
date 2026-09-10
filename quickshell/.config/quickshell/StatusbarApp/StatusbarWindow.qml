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
import qs.SidebarApp
import qs.ClipboardApp
import qs.NotificationsApp
import qs.MediaApp
import qs.WallpaperApp
import qs.SettingsApp

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
    //   1. ~/.config/ml4w-statusbar/statusbar.json — the user override. When this
    //      file EXISTS it is the master: every value is read from it and the
    //      Sidebar switches write their changes (enabled / alwaysExpanded) back
    //      into it. The shipped file is ignored while it exists.
    //   2. ~/.config/ml4w/settings/statusbar.json — the shipped fallback, used
    //      only when the override file is absent. It carries the dynamic state
    //      the SidebarApp writes (bar.enabled and bar.alwaysExpanded).
    //
    // The active master file is merged over the built-in defaults, so a partial
    // or entirely missing file still leaves every value defined.
    readonly property var defaultSettings: ({
        "bar":    { "height": 36, "reservedHeight": 36, "enabled": true, "alwaysExpanded": false },
        "pill":   { "collapsedWidth": 0, "expandedWidth": 680, "radius": 18, "flareRadius": 18, "animationDuration": 350 },
        "modules":{ "left": ["terminal", "workspaces"],
                    "center": ["launcher", "clock", "swaync"],
                    "right": ["updates", "battery", "powerprofile", "volume", "systemtray", "keyboard", "clipboard", "power"] },
        "border": { "width": 0, "colorTop": "", "colorBottom": "" },
        "opacity":{ "collapsed": 0.82, "expanded": 0.9 },
        "clock":  { "format": "HH:mm", "dateFormat": "ddd, dd MMM" },
        "workspaces": { "count": 5, "showAppIcons": true },
        // Free-text place name for the notification panel's weather. Anything
        // after the first comma is a hint used to pick between same-named
        // places (e.g. "Belfast, UK" vs "Belfast, US").
        "weather": { "location": "Belfast, UK" }
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
        path: Quickshell.env("HOME") + "/.config/ml4w-statusbar/statusbar.json"
        blockLoading: true
        printErrors: false
        onLoaded: { root.overrideExists = true; root.applySettings() }
        onLoadFailed: { root.overrideExists = false; root.applySettings() }
    }

    // Shipped fallback holding the dynamic state (enabled / alwaysExpanded), used
    // only when the override file is absent. Changes are not picked up
    // automatically; trigger a re-read explicitly with
    //   qs ipc call statusbar reload
    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/ml4w/settings/statusbar.json"
        blockLoading: true
        onLoaded: root.applySettings()
    }

    // The active master file: the override when it exists, otherwise the shipped
    // file. The Sidebar switches write here and applySettings reads from here.
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

    // Persist a bar.<key> boolean into the master file and return the updated
    // text. A regex replace is used when the key is already present (so the
    // file's formatting/comments are kept); when the key is missing (e.g. an
    // override file that did not list it) it falls back to a JSON rewrite of the
    // parsed document. If the file cannot be parsed at all the write is skipped
    // rather than replaced with an empty object, so a malformed hand-edited
    // override is never wiped — its current text is returned unchanged.
    function persistBarFlag(key, on): string {
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
            if (obj.bar === undefined)
                obj.bar = {}
            obj.bar[key] = on
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
    // single source of truth; it is toggled from the SidebarApp switch and via
    // "qs ipc call statusbar toggle", persisted back to the file, and survives
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
        applySettings(persistBarFlag("enabled", on))
    }

    // Keep the pill expanded regardless of hover. Set via IPC
    // ("qs ipc call statusbar focus") which is bound to SUPER + SPACE in
    // Hyprland, and cleared on Escape, after running a module, or when the
    // focus grab is released because the user interacted with another window.
    property bool barExpanded: false

    // When set in statusbar.json the pill never collapses: it stays in its
    // expanded (full-width) state independent of hover or the IPC toggle. This
    // is purely visual — unlike barExpanded it does not grab the keyboard — so
    // the left/right module areas remain permanently visible.
    property bool alwaysExpanded: settings.bar.alwaysExpanded

    // Persist the alwaysExpanded state into the master file and apply it.
    // Mirrors setEnabled.
    function setAlwaysExpanded(on: bool): void {
        applySettings(persistBarFlag("alwaysExpanded", on))
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
        }
    }
    Component { id: cLauncher;   LauncherModule {} }
    Component {
        id: cClock
        ClockModule {
            expanded: pill.expanded
            timeFormat: root.settings.clock.format
            dateFormat: root.settings.clock.dateFormat
            onToggleRequested: root.togglePanel("calendar")
        }
    }
    Component { id: cSwaync;     SwayncModule {} }
    Component {
        id: cMedia
        MediaModule {
            // Rebuild the keyboard navigation list when a player appears or
            // goes away (the module folds out of the layout with it).
            onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
            onClicked: root.togglePanel("media")
        }
    }
    Component {
        id: cNotifications
        NotificationsModule {
            onClicked: root.togglePanel("notifications")
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
    Component { id: cVolume;     VolumeModule {} }
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
        }
    }

    readonly property var moduleComponents: ({
        "terminal":   cTerminal,
        "workspaces": cWorkspaces,
        "launcher":   cLauncher,
        "clock":      cClock,
        "swaync":     cSwaync,
        "notifications": cNotifications,
        "media":         cMedia,
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

    // True while a panel is flush with the bar's right edge, so the bar can
    // merge its silhouette into it.
    readonly property bool rightEdgePanelOpen: root.openPanel === "power"

    function closePanel(name: string): void {
        if (root.openPanel === name)
            root.openPanel = ""
    }

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

    Component.onCompleted: Qt.callLater(rebuildNavItems)
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

    // The calendar, power menu and sidebar used to be windows of their own,
    // each with its own IPC target. They are panels of the bar now, but the
    // targets are kept exactly as they were so the existing Hyprland
    // keybindings — and the Sidebar's own buttons — keep working.
    IpcHandler {
        target: "calendar"
        function toggle(): void { root.togglePanel("calendar") }
        function open(): void { root.openPanel = "calendar" }
        function close(): void { root.closePanel("calendar") }
        function isOpen(): bool { return root.openPanel === "calendar" }
    }

    IpcHandler {
        target: "power"
        function toggle(): void { root.togglePanel("power") }
        function open(): void { root.openPanel = "power" }
        function close(): void { root.closePanel("power") }
        function isOpen(): bool { return root.openPanel === "power" }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { root.togglePanel("wallpaper") }
        function open(): void { root.openPanel = "wallpaper" }
        function close(): void { root.closePanel("wallpaper") }
        function isOpen(): bool { return root.openPanel === "wallpaper" }
    }

    IpcHandler {
        target: "media"
        function toggle(): void { root.togglePanel("media") }
        function open(): void { root.openPanel = "media" }
        function close(): void { root.closePanel("media") }
        function isOpen(): bool { return root.openPanel === "media" }
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { root.togglePanel("notifications") }
        function open(): void { root.openPanel = "notifications" }
        function close(): void { root.closePanel("notifications") }
        function isOpen(): bool { return root.openPanel === "notifications" }
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.togglePanel("clipboard") }
        function open(): void { root.openPanel = "clipboard" }
        function close(): void { root.closePanel("clipboard") }
        function isOpen(): bool { return root.openPanel === "clipboard" }
    }

    IpcHandler {
        target: "sidebar"
        function toggle(): void { root.togglePanel("sidebar") }
        function open(): void { root.openPanel = "sidebar" }
        function close(): void { root.closePanel("sidebar") }
        function isOpen(): bool { return root.openPanel === "sidebar" }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { root.togglePanel("settings") }
        function open(): void { root.openPanel = "settings" }
        function close(): void { root.closePanel("settings") }
        function isOpen(): bool { return root.openPanel === "settings" }
    }

    IpcHandler {
        target: "statusbar"
        function toggle(): void { root.setEnabled(!root.settings.bar.enabled) }
        // Named enable/disable rather than show/hide: "show" is a reserved
        // subcommand of "qs ipc" and would never reach the function.
        function enable(): void { root.setEnabled(true) }
        function disable(): void { root.setEnabled(false) }
        // Persist and apply the alwaysExpanded (permanently expanded) mode,
        // toggled from the SidebarApp switch.
        function alwaysExpand(): void { root.setAlwaysExpanded(true) }
        function autoCollapse(): void { root.setAlwaysExpanded(false) }
        // Re-read statusbar.json from disk (used by the SidebarApp switch).
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
        property real collapsedWidth: root.settings.pill.collapsedWidth > 0
            ? root.settings.pill.collapsedWidth
            : centerArea.implicitWidth + 32

        // Minimum width the content needs so the centered center area never
        // overlaps the left/right areas. The center stays centered, so each
        // side must clear half of it: the bar has to be at least as wide as the
        // center plus twice the wider of the two side areas (whichever side
        // would collide first), plus the 16px edge margins and some breathing
        // room. Computed live so adding workspaces (or any module growing)
        // pushes the bar wider instead of clipping.
        property real contentWidth: centerArea.implicitWidth
            + 2 * Math.max(leftArea.implicitWidth, rightArea.implicitWidth)
            + 64
        // expandedWidth from the settings file is treated as a minimum: the
        // pill grows past it when the content needs more room.
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
        RowLayout {
            id: leftArea
            anchors.left: parent.left
            anchors.leftMargin: pill.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

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
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: root.moduleComponents[modelData] || null
                    onLoaded: Qt.callLater(root.rebuildNavItems)
                }
            }
        }

        // ==========================================
        // CENTER AREA (always visible)
        // ==========================================
        RowLayout {
            id: centerArea
            anchors.centerIn: parent
            spacing: 14

            Repeater {
                id: centerRepeater
                model: root.settings.modules.center
                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: root.moduleComponents[modelData] || null
                    onLoaded: Qt.callLater(root.rebuildNavItems)
                }
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
            spacing: 14

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
        }

        BarDropdown {
            id: calendarPanel
            // Falls back to the centre group if the clock has been removed from
            // the bar, so the keybinding still puts the calendar somewhere sane.
            anchorItem: root.moduleRefs["clock"] || centerArea
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
            // Opened by a keybinding and by the sidebar, with no icon of its
            // own, so it drops from the middle of the bar.
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
            id: notificationsPanel
            // Dropped from the middle of the bar, like the other wide panels.
            anchorItem: pill
            open: root.openPanel === "notifications"
            onDismissed: root.closePanel("notifications")
            panelWidth: 420
            panelHeight: 528
            panelContent: Component {
                NotificationPanel {
                    isOpen: root.openPanel === "notifications"
                    location: root.settings.weather.location
                    onCloseRequested: root.closePanel("notifications")
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
            id: sidebarPanel
            // The sidebar has no icon of its own — it is opened by a
            // keybinding — so it drops from the middle of the bar, where both
            // its flares land on the bar's flat underside.
            anchorItem: pill
            open: root.openPanel === "sidebar"
            onDismissed: root.closePanel("sidebar")
            panelWidth: 420
            // As tall as it can be without running off the bottom of the
            // screen; the panel's own scroll area carries the rest.
            panelHeight: Math.min(760, root.screen.height - root.barHeight - 72)
            panelContent: Component {
                SidebarPanel {
                    isOpen: root.openPanel === "sidebar"
                    onCloseRequested: root.closePanel("sidebar")
                }
            }
        }

        BarDropdown {
            id: settingsPanel
            // Opened from the sidebar and by IPC, with no icon of its own, so it
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
