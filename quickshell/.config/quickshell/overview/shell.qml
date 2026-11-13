//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QPA_PLATFORMTHEME=

import "./modules/overview/"
import "./services/"
import "./common/"
import "./common/functions/"
import "./common/widgets/"

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    Connections {
        target: Quickshell

        function onReloadCompleted() {
            Quickshell.inhibitReloadPopup();
        }
    }

    Overview {}

    // Standalone use only (qs -p ~/.config/quickshell/overview). The main
    // shell loads this module itself and has its own copy of this handler.
    IpcHandler {
        target: "overview"
        function toggle() { GlobalStates.overviewOpen = !GlobalStates.overviewOpen }
        function close() { GlobalStates.overviewOpen = false }
        function open() { GlobalStates.overviewOpen = true }
    }
}
