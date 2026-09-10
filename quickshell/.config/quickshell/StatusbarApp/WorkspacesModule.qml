import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme

// Hyprland workspace switcher.
//
// The focused workspace always shows its number. Every other workspace that
// holds windows shows the icon of the application running in it (the most
// recently focused one when it holds several); workspaces that are empty fall
// back to their number, dimmed.
RowLayout {
    id: wsRoot
    spacing: 6

    // Minimum number of workspaces to always display, even when empty. The list
    // still grows beyond this to reveal any higher-numbered workspace that
    // exists (e.g. switching to workspace 6 while this is 5 adds a 6th dot).
    property int minWorkspaces: 5

    // Master switch for the per-workspace application icons. When off the
    // module renders plain numbers, as it did before.
    property bool showAppIcons: true

    // Window classes that are terminals. A terminal's class says nothing about
    // what is actually running in it, so for these the *process tree* under the
    // window is inspected instead (see foregroundApp) — that is what turns a
    // kitty window running nvim, btop or yazi into that program's icon rather
    // than a second terminal icon.
    property var terminalClasses: ["kitty", "alacritty", "foot", "footclient",
        "wezterm", "org.wezfurlong.wezterm", "ghostty", "com.mitchellh.ghostty",
        "konsole", "gnome-terminal", "xterm", "urxvt", "st", "terminator",
        "tilix", "wayst", "org.gnome.console", "com.raggesilver.blackbox"]

    // Processes that are plumbing rather than "the app you are running":
    // shells, the terminal's own helpers, privilege wrappers and language
    // runtimes that almost always front for something else. They are stepped
    // over when looking for what a terminal is running.
    property var ignoredProcesses: ["sh", "bash", "zsh", "fish", "dash", "ksh",
        "tcsh", "csh", "nu", "elvish", "xonsh", "kitten", "zsh-autosuggest",
        "login", "su", "sudo", "doas", "env", "tmux", "tmux: server", "screen",
        "ps", "sleep", "cat", "grep", "sed", "awk", "which", "starship",
        "node", "python", "python3", "npm", "npx", "deno", "bun", "ruby",
        "perl", "java", "dotnet", "systemd-cat"]

    // Process name -> icon name, for programs whose executable is not also the
    // name of an icon in the theme. Anything not listed here falls back to an
    // icon named exactly like the process, then to its desktop entry.
    property var termApps: ({
        "nvim": "nvim",
        "vi": "vim",
        "lazygit": "git",
        "tig": "git",
        "gitui": "git",
        "yazi": "system-file-manager",
        "ranger": "system-file-manager",
        "lf": "system-file-manager",
        "nnn": "system-file-manager",
        "mc": "system-file-manager",
        "top": "utilities-system-monitor",
        "nvtop": "utilities-system-monitor",
        "neomutt": "internet-mail",
        "mutt": "internet-mail",
        "ncmpcpp": "multimedia-player",
        "cmus": "multimedia-player",
        "man": "text-x-generic",
        "less": "text-x-generic"
    })

    // Substring of a window title (matched case-insensitively) -> icon name,
    // used as a fallback for terminals when the process tree turns up nothing
    // recognisable. First match wins, so order the more specific keys first.
    property var titleIcons: ({
        "nvim": "nvim",
        "neovim": "nvim",
        "btop": "btop",
        "htop": "htop",
        "yazi": "system-file-manager",
        "ranger": "system-file-manager",
        "lazygit": "git",
        "vim": "vim"
    })

    // The individual workspace buttons, exposed so StatusbarWindow can splice
    // them into its keyboard-navigation list. Rebuilt whenever workspaces are
    // added or removed.
    property var navButtons: []

    function rebuildNavButtons(): void {
        let a = []
        for (let i = 0; i < rep.count; i++)
            a.push(rep.itemAt(i))
        wsRoot.navButtons = a
    }

    // --- KEEPING THE WINDOW LIST FRESH ---
    // Hyprland.toplevels tracks which windows exist, but the per-window details
    // this module needs (class, pid, focus order) live in lastIpcObject, which
    // is only filled in by an explicit refresh. Without one, a window opened
    // after startup stays undefined forever and focusHistoryID goes stale, so
    // the bar keeps showing the workspace number instead of the new app's icon.
    // Refreshing is therefore driven off Hyprland's own event stream.

    Component.onCompleted: {
        Hyprland.refreshToplevels()
        Hyprland.refreshWorkspaces()
        procScan.running = true
    }

    // Events that change *which* windows exist, where they live, or which one
    // is focused. Title changes are deliberately excluded: a program that
    // rewrites its title continuously (a progress spinner, a shell prompt)
    // would otherwise trigger a refresh several times a second. Those cases are
    // picked up by the process scan below instead.
    readonly property var refreshEvents: ["openwindow", "closewindow",
        "movewindow", "movewindowv2", "activewindow", "activewindowv2",
        "workspace", "workspacev2", "createworkspace", "createworkspacev2",
        "destroyworkspace", "destroyworkspacev2", "focusedmon", "focusedmonv2",
        "fullscreen", "changefloatingmode", "moveworkspace", "moveworkspacev2"]

    Connections {
        target: Hyprland
        function onRawEvent(event): void {
            if (wsRoot.refreshEvents.indexOf(event.name) >= 0)
                refreshDebounce.restart()
        }
    }

    // Hyprland fires several events for one user action (e.g. openwindow +
    // activewindow + workspace); coalesce them into a single refresh.
    Timer {
        id: refreshDebounce
        interval: 120
        onTriggered: {
            Hyprland.refreshToplevels()
            Hyprland.refreshWorkspaces()
            procScan.running = true
        }
    }

    // --- WHAT IS RUNNING INSIDE A TERMINAL ---
    // One cheap process listing, walked in QML to find the program each
    // terminal window is fronting for. Re-run on every window event and on a
    // slow heartbeat, which is what catches a program started inside a terminal
    // that is already open (that produces no Hyprland event at all).
    Timer {
        interval: 5000
        running: wsRoot.visible && wsRoot.showAppIcons
        repeat: true
        onTriggered: procScan.running = true
    }

    Process {
        id: procScan
        command: ["ps", "-eo", "pid,ppid,comm", "--no-headers"]
        stdout: StdioCollector {
            onStreamFinished: wsRoot.psTree = wsRoot.parsePs(this.text)
        }
    }

    // { kids: { ppid: [pid, ...] }, comms: { pid: "name" } }
    property var psTree: ({ kids: ({}), comms: ({}) })

    function parsePs(text: string): var {
        let kids = ({})
        let comms = ({})
        const lines = (text || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            // "  1234  5678 some command" — the name may contain spaces.
            const m = /^\s*(\d+)\s+(\d+)\s+(.+?)\s*$/.exec(lines[i])
            if (!m)
                continue
            const pid = parseInt(m[1])
            const ppid = parseInt(m[2])
            comms[pid] = m[3]
            if (kids[ppid] === undefined)
                kids[ppid] = []
            kids[ppid].push(pid)
        }
        return { kids: kids, comms: comms }
    }

    // The program a terminal window is running, or "" when it is just a shell.
    // Breadth-first from the window's own process so the *nearest* interesting
    // descendant wins: a short-lived helper spawned deeper in the tree (a `ps`
    // from a script, say) never outranks the program the user is actually
    // looking at.
    function foregroundApp(rootPid: int): string {
        const kids = wsRoot.psTree.kids
        const comms = wsRoot.psTree.comms
        if (!rootPid || kids[rootPid] === undefined)
            return ""
        let queue = kids[rootPid].slice()
        let guard = 0
        while (queue.length > 0 && guard++ < 500) {
            const pid = queue.shift()
            const name = comms[pid] || ""
            if (name !== "" && wsRoot.ignoredProcesses.indexOf(name) < 0)
                return name
            if (kids[pid] !== undefined)
                queue = queue.concat(kids[pid])
        }
        return ""
    }

    // Icon source for a program name, trying the explicit mapping first, then
    // an icon named like the program, then its desktop entry. "" when nothing
    // matched.
    function iconForName(name: string): string {
        if (!name)
            return ""
        const mapped = wsRoot.termApps[name]
        if (mapped !== undefined) {
            let hit = Quickshell.iconPath(mapped, true)
            if (hit !== "")
                return hit
        }
        let hit = Quickshell.iconPath(name, true)
        if (hit !== "")
            return hit
        const entry = DesktopEntries.heuristicLookup(name)
        if (entry && entry.icon) {
            hit = Quickshell.iconPath(entry.icon, true)
            if (hit !== "")
                return hit
        }
        return ""
    }

    // Resolve one window to an icon source usable by IconImage. Returns ""
    // when nothing sensible was found, which makes the delegate fall back to
    // the workspace number.
    function resolveIcon(cls: string, title: string, pid: int): string {
        const lowCls = (cls || "").toLowerCase()
        if (lowCls === "")
            return ""

        // A terminal is a container, not an application: prefer whatever is
        // running inside it over the terminal's own icon.
        if (wsRoot.terminalClasses.indexOf(lowCls) >= 0) {
            let hit = wsRoot.iconForName(wsRoot.foregroundApp(pid))
            if (hit !== "")
                return hit

            // Nothing conclusive in the process tree (or ps unavailable): fall
            // back to what the terminal put in its title.
            const lowTitle = (title || "").toLowerCase()
            for (let key in wsRoot.titleIcons) {
                if (lowTitle.indexOf(key.toLowerCase()) >= 0) {
                    hit = Quickshell.iconPath(wsRoot.titleIcons[key], true)
                    if (hit !== "")
                        return hit
                }
            }
            // Otherwise fall through and use the terminal's own icon.
        }

        // Normal case: the desktop entry for the window class carries the icon.
        const entry = DesktopEntries.heuristicLookup(cls)
        if (entry && entry.icon) {
            let hit = Quickshell.iconPath(entry.icon, true)
            if (hit !== "")
                return hit
        }

        // Last resort: many apps ship an icon named exactly like their class.
        return Quickshell.iconPath(lowCls, true)
    }

    // The workspace ids to render: 1..N, where N is at least minWorkspaces and
    // extends to cover the highest-numbered workspace that currently exists.
    readonly property var workspaceIds: {
        let maxId = Math.max(1, wsRoot.minWorkspaces)
        const list = Hyprland.workspaces.values
        for (let i = 0; i < list.length; i++)
            if (list[i].id > maxId)
                maxId = list[i].id
        let ids = []
        for (let id = 1; id <= maxId; id++)
            ids.push(id)
        return ids
    }

    // The live Hyprland workspace for an id, or null when it is empty (Hyprland
    // only tracks workspaces that hold windows or are focused).
    function workspaceById(id: int): var {
        const list = Hyprland.workspaces.values
        for (let i = 0; i < list.length; i++)
            if (list[i].id === id)
                return list[i]
        return null
    }

    // workspace id -> icon source for the application to represent it with.
    // When a workspace holds several windows the most recently focused one wins
    // (Hyprland's focusHistoryID: 0 is the active window, and it counts up).
    readonly property var appIcons: {
        let icons = ({})
        if (!wsRoot.showAppIcons)
            return icons
        // Referenced so this binding re-runs when the process scan lands.
        const tree = wsRoot.psTree
        let ranks = ({})
        const tops = Hyprland.toplevels.values
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            const ipc = t.lastIpcObject
            let wsId = t.workspace ? t.workspace.id : -1
            if (wsId < 0 && ipc && ipc.workspace)
                wsId = ipc.workspace.id
            if (wsId < 0)
                continue
            const rank = (ipc && ipc.focusHistoryID !== undefined)
                ? ipc.focusHistoryID : 9999
            if (ranks[wsId] !== undefined && ranks[wsId] <= rank)
                continue
            // wayland.appId is available before the first IPC refresh lands, so
            // a freshly opened window still gets an icon on the next frame.
            let cls = ipc ? (ipc["class"] || ipc.initialClass || "") : ""
            if (cls === "" && t.wayland)
                cls = t.wayland.appId || ""
            const icon = wsRoot.resolveIcon(cls, t.title || "",
                ipc ? (ipc.pid || 0) : 0)
            if (icon === "")
                continue
            ranks[wsId] = rank
            icons[wsId] = icon
        }
        return icons
    }

    Repeater {
        id: rep
        model: wsRoot.workspaceIds

        onItemAdded: wsRoot.rebuildNavButtons()
        onItemRemoved: wsRoot.rebuildNavButtons()

        delegate: Rectangle {
            id: ws
            required property var modelData   // the workspace id (int)
            // Set by StatusbarWindow's keyboard navigation.
            property bool focused: false

            // Whether this workspace is the currently focused one.
            readonly property bool isActive: Hyprland.focusedWorkspace
                && Hyprland.focusedWorkspace.id === ws.modelData
            // Whether the workspace currently holds windows (exists in Hyprland).
            readonly property bool occupied: wsRoot.workspaceById(ws.modelData) !== null

            // The application icon standing in for this workspace, or "" when
            // there is none (empty workspace, or an app whose icon we could not
            // resolve). The focused workspace always keeps its number so the
            // current position stays readable at a glance.
            readonly property string appIcon: (ws.isActive || !wsRoot.showAppIcons)
                ? "" : (wsRoot.appIcons[ws.modelData] || "")
            readonly property bool showsIcon: ws.appIcon !== ""

            // Run this workspace's action (mouse click or keyboard Return).
            // Hyprland with Lua dispatchers ignores the plain "workspace N"
            // string, so branch on usingLua the same way the overview does.
            function activate(): void {
                if (Hyprland.usingLua)
                    Hyprland.dispatch("hl.dsp.focus({workspace = '" + ws.modelData + "'})")
                else
                    Hyprland.dispatch("workspace " + ws.modelData)
            }

            implicitWidth: 26
            implicitHeight: 26
            radius: 13

            // Empty, unfocused workspaces are dimmed to set them apart from the
            // ones that hold windows.
            opacity: (ws.isActive || ws.occupied || wsMouse.containsMouse) ? 1 : 0.45
            Behavior on opacity {
                NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
            }

            color: ws.isActive
                ? Theme.primary
                : (wsMouse.containsMouse ? Theme.surface_container_high : "transparent")
            border.color: Theme.primary
            // The icon carries the "occupied" signal on its own, so the outline
            // is dropped there to keep the row from looking busy.
            border.width: (ws.isActive || ws.showsIcon) ? 0 : 1

            // Crossfade the fill between active / hover / inactive states so the
            // background of the active circle fades in and the previous one out.
            Behavior on color {
                ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
            }
            // Fade the outline in/out as the fill takes over on activation.
            Behavior on border.width {
                NumberAnimation { duration: 500; easing.type: Easing.OutQuint }
            }

            // Keyboard-selection ring, distinct from the active-workspace fill.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: width / 2
                color: "transparent"
                border.color: Theme.primary
                border.width: 2
                opacity: ws.focused ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
            }

            // Application icon, shown in place of the number for occupied,
            // unfocused workspaces. Kept in its own colors so the apps stay
            // recognisable against the themed bar.
            IconImage {
                anchors.centerIn: parent
                implicitSize: 17
                source: ws.appIcon
                visible: opacity > 0
                opacity: ws.showsIcon ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
                }
            }

            Text {
                anchors.centerIn: parent
                text: ws.modelData
                color: ws.isActive ? Theme.background : Theme.on_background
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true

                visible: opacity > 0
                opacity: ws.showsIcon ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
                }

                // Match the fill crossfade so the label recolors in step.
                Behavior on color {
                    ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
                }
            }

            MouseArea {
                id: wsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ws.activate()
            }
        }
    }
}
