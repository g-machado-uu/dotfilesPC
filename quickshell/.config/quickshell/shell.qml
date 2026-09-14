//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import "StatusbarApp"
import "DesktopWidget"
import "CustomTheme"

ShellRoot {
    // Test IPC tools: qs ipc show

    IpcHandler {
        target: "theme-manager"
        function reload(): void {
            Theme.reloadTheme()
            // The widget picks its text colour from the wallpaper rather than
            // from the theme, so a theme reload is a good moment to look again.
            desktopWidget.sampleWallpaper()
        }
    }

    // Declared before the bar so the bar's surface is mapped last and therefore
    // stacked above it: the widget's sections then disappear *underneath* the
    // bar as they are sucked in, instead of sliding over the top of it.
    DesktopWidgetWindow {
        id: desktopWidget

        barHeight: bar.visible ? bar.reservedHeight : 0
        location: bar.settings.weather.location
        widgetEnabled: bar.weatherWidgetEnabled
        timeFormat: bar.settings.clock.format
        // The widget deliberately stays out while a bar panel is dropped. The
        // panels belong to the bar and are drawn over the top of it, so they
        // are legible against the widget; sending the widget away instead meant
        // the clock jumped back into the bar every time the settings, wallpaper
        // or power panel was opened, and jumped out again on closing.
    }

    StatusbarWindow {
        id: bar

        // The widget owns the clock while it is on screen.
        hideClock: desktopWidget.hideBarClock
    }
}
