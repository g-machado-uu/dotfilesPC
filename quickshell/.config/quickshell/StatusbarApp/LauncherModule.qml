import QtQuick

// Application launcher icon. The panel it opens (LauncherApp) hangs off this
// button and is wired up by the status bar, so there is no action here. The
// old rofi launcher is still on SUPER + CTRL + RETURN (hypr/scripts/launcher.sh).
BarButton {
    iconSrc: "../shared/icons/launcher.svg"
}
