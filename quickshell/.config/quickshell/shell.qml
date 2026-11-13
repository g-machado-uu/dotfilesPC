//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import QtQuick
import "StatusbarApp"
import "DesktopWidget"
import "CustomTheme"
import "overview/modules/overview" as OverviewModule
import "overview/services" as OverviewState
import "NotificationApp"

ShellRoot {
    id: shell

    // Test IPC tools: qs ipc show

    // --- NOTIFICATIONS ---
    // The shell's notification daemon (it replaced swaync). Named here so it
    // is created with the shell itself: it is a singleton, so it would
    // otherwise only come up when something first read it — which is a bar
    // module, and the daemon should not depend on the bar's module list.
    readonly property var notifications: NotificationService

    IpcHandler {
        target: "theme-manager"
        function reload(): void {
            Theme.reloadTheme()
            // The widget picks its text colour from the wallpaper rather than
            // from the theme, so a theme reload is a good moment to look again.
            desktopWidget.sampleWallpaper()
        }
    }

    // --- WORKSPACE OVERVIEW (SUPER + TAB) ---
    // Used to run as its own `qs -p overview` process, which meant a second
    // copy of Qt in memory all session. It now lives here, and is only built
    // while it is in use: created on the first open and released again once it
    // has been closed for overviewIdleMs, which takes its window previews
    // (ScreencopyView buffers) with it.
    readonly property int overviewIdleMs: 60000

    function setOverview(on: bool): void {
        if (on) {
            overviewIdle.stop()
            // LazyLoader builds synchronously when activated, so the windows
            // exist before the open flag flips and see it change.
            overviewLoader.active = true
        }
        OverviewState.GlobalStates.overviewOpen = on
    }

    LazyLoader {
        id: overviewLoader
        active: false
        OverviewModule.Overview {}
    }

    Timer {
        id: overviewIdle
        interval: shell.overviewIdleMs
        onTriggered: overviewLoader.active = false
    }

    Connections {
        target: OverviewState.GlobalStates
        function onOverviewOpenChanged(): void {
            if (!OverviewState.GlobalStates.overviewOpen)
                overviewIdle.restart()
        }
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { shell.setOverview(!OverviewState.GlobalStates.overviewOpen) }
        function open(): void { shell.setOverview(true) }
        function close(): void { shell.setOverview(false) }
    }

    // The bar that shares a screen with the widget: it feeds the widget its
    // settings and is the one that folds its clock away.
    readonly property var mainBar: bars.instances.find(b => b.isPrimary) ?? null

    // Declared before the bars so their surfaces are mapped last and therefore
    // stacked above it: the widget's sections then disappear *underneath* the
    // bar as they are sucked in, instead of sliding over the top of it.
    DesktopWidgetWindow {
        id: desktopWidget

        // One widget only, on the first screen (the laptop panel, or whichever
        // monitor is left when the lid is closed). It samples the wallpaper and
        // fetches the weather itself, so a copy per monitor would double both.
        screen: Quickshell.screens[0]
        barHeight: shell.mainBar && shell.mainBar.visible ? shell.mainBar.reservedHeight : 0
        location: shell.mainBar ? shell.mainBar.settings.weather.location : "Belfast, UK"
        widgetEnabled: shell.mainBar ? shell.mainBar.weatherWidgetEnabled : false
        timeFormat: shell.mainBar ? shell.mainBar.settings.clock.format : "HH:mm"
        uiScale: shell.mainBar ? shell.mainBar.settings.weather.widgetScale : 0.8
        showDelay: shell.mainBar ? shell.mainBar.settings.weather.showDelay : 600
        // The widget deliberately stays out while a bar panel is dropped. The
        // panels belong to the bar and are drawn over the top of it, so they
        // are legible against the widget; sending the widget away instead meant
        // the clock jumped back into the bar every time the settings, wallpaper
        // or power panel was opened, and jumped out again on closing.
    }

    // One bar per monitor, including monitors plugged in later.
    Variants {
        id: bars
        model: Quickshell.screens

        StatusbarWindow {
            required property var modelData
            screen: modelData
            isPrimary: modelData === desktopWidget.screen

            // The widget owns the clock while it is on screen, but only the
            // bar on the widget's own screen gives it up.
            hideClock: isPrimary && desktopWidget.hideBarClock
        }
    }
}
