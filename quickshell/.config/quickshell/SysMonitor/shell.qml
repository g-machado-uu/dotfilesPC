//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: shell

    // ============================================================
    //  PALETTE  (matugen -> ~/.config/ml4w/colors/colors.json)
    // ============================================================
    QtObject {
        id: pal
        readonly property string fontFamily: "Fira Sans"

        property color background: "#111318"
        property color error: "#ffb4ab"
        property color on_surface: "#e1e2e9"
        property color on_surface_variant: "#c3c6cf"
        property color outline: "#8d9199"
        property color outline_variant: "#43474e"
        property color primary: "#a5c8fe"
        property color scrim: "#000000"
        property color secondary: "#bcc7dc"
        property color surface_container: "#1d2024"
        property color surface_container_lowest: "#0c0e13"
        property color tertiary: "#d9bde2"
    }

    // Blocking read at startup so the bubbles are never drawn with fallback colors.
    FileView {
        id: colorFile
        path: Quickshell.env("HOME") + "/.config/ml4w/colors/colors.json"
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        try {
            const c = JSON.parse(colorFile.text());
            for (const k in c)
                if (pal.hasOwnProperty(k)) pal[k] = c[k];
        } catch (e) { /* keep the fallback palette */ }
    }

    // ============================================================
    //  SYSTEM METRICS
    // ============================================================
    QtObject {
        id: sys
        property real cpuUsage: 0
        property real cpuMhz: 0
        property int cpuThreads: 0

        property real cpuTemp: 0
        property real cpuTempMax: 100

        property real memUsed: 0        // GiB
        property real memTotal: 0
        property real memAvail: 0

        property bool igpuOk: false
        property real igpuBusy: 0       // 0..1, from RC6 residency
        property real igpuFreq: 0       // actual clock, 0 while the GT is parked
        property real igpuFreqReq: 0    // requested clock
        property real igpuFreqMax: 0

        property bool gpuOk: false
        property real gpuUtil: 0        // 0..1
        property real gpuClock: 0
        property real gpuClockMax: 1
        property real vramUsed: 0       // GiB
        property real vramTotal: 0
        property real gpuTemp: 0
        property real gpuPower: 0
        property real gpuPowerMax: 0
        property real gpuMemClock: 0

        function pct(v) { return Math.round(Math.max(0, Math.min(1, v)) * 100); }
        function gib(v) { return v >= 10 ? v.toFixed(1) : v.toFixed(2); }
    }

    // ---- CPU: /proc/stat deltas -------------------------------------------
    property var prevCpu: null
    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const line = text().split("\n")[0].trim().split(/\s+/);
            let total = 0;
            for (let i = 1; i < line.length; i++) total += parseInt(line[i]) || 0;
            const idle = (parseInt(line[4]) || 0) + (parseInt(line[5]) || 0);
            if (shell.prevCpu) {
                const dt = total - shell.prevCpu.total;
                const di = idle - shell.prevCpu.idle;
                if (dt > 0) sys.cpuUsage = Math.max(0, Math.min(1, 1 - di / dt));
            }
            shell.prevCpu = { total: total, idle: idle };
        }
    }

    FileView {
        id: cpuInfoFile
        path: "/proc/cpuinfo"
        printErrors: false
        onLoaded: {
            const m = text().match(/cpu MHz\s*:\s*([\d.]+)/g);
            if (!m || m.length === 0) return;
            let sum = 0;
            for (const l of m) sum += parseFloat(l.split(":")[1]);
            sys.cpuMhz = sum / m.length;
            sys.cpuThreads = m.length;
        }
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            const t = text();
            const total = parseInt((t.match(/MemTotal:\s*(\d+)/) || [0, 0])[1]);
            const avail = parseInt((t.match(/MemAvailable:\s*(\d+)/) || [0, 0])[1]);
            sys.memTotal = total / 1048576;
            sys.memAvail = avail / 1048576;
            sys.memUsed = (total - avail) / 1048576;
        }
    }

    // ---- integrated GPU: i915 RC6 residency tells us how much of the last
    //      interval the render engine spent parked in its idle power state ----
    property string igpuDir: ""
    property real prevRc6: -1
    property real prevRc6At: 0
    Process {
        running: true
        command: ["bash", "-c",
            "for c in /sys/class/drm/card[0-9]; do " +
            "  [ -r \"$c/power/rc6_residency_ms\" ] && { echo \"$c\"; exit 0; }; " +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const dir = this.text.trim();
                if (dir === "") return;
                igpuMaxFile.path = dir + "/gt_max_freq_mhz";
                igpuFreqFile.path = dir + "/gt_act_freq_mhz";
                igpuReqFile.path = dir + "/gt_cur_freq_mhz";
                shell.igpuDir = dir + "/power/rc6_residency_ms";
            }
        }
    }

    FileView {
        id: rc6File
        path: shell.igpuDir
        printErrors: false
        onLoaded: {
            const ms = parseFloat(text());
            const now = Date.now();
            if (isNaN(ms)) return;
            if (shell.prevRc6 >= 0) {
                const dt = now - shell.prevRc6At;
                if (dt > 0) sys.igpuBusy = Math.max(0, Math.min(1, 1 - (ms - shell.prevRc6) / dt));
            }
            shell.prevRc6 = ms;
            shell.prevRc6At = now;
            sys.igpuOk = true;
        }
    }

    FileView {
        id: igpuFreqFile
        printErrors: false
        onLoaded: { const v = parseFloat(text()); if (!isNaN(v)) sys.igpuFreq = v; }
    }

    FileView {
        id: igpuReqFile
        printErrors: false
        onLoaded: { const v = parseFloat(text()); if (!isNaN(v)) sys.igpuFreqReq = v; }
    }

    FileView {
        id: igpuMaxFile
        printErrors: false
        onLoaded: { const v = parseFloat(text()); if (!isNaN(v)) sys.igpuFreqMax = v; }
    }

    // ---- CPU temperature: whichever hwmon exposes the package sensor --------
    property string cpuTempPath: ""
    Process {
        running: true
        command: ["bash", "-c",
            "for h in /sys/class/hwmon/*; do " +
            "  n=$(cat \"$h/name\" 2>/dev/null); " +
            "  case \"$n\" in coretemp|k10temp|zenpower|cpu_thermal|acpitz) " +
            "    [ -r \"$h/temp1_input\" ] && { echo \"$h\"; exit 0; };; esac; " +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const dir = this.text.trim();
                if (dir === "") return;
                critFile.path = dir + "/temp1_crit";
                shell.cpuTempPath = dir + "/temp1_input";
            }
        }
    }

    FileView {
        id: cpuTempFile
        path: shell.cpuTempPath
        printErrors: false
        onLoaded: {
            const v = parseFloat(text());
            if (!isNaN(v)) sys.cpuTemp = v / 1000;
        }
    }

    FileView {
        id: critFile
        printErrors: false
        onLoaded: {
            const v = parseFloat(text());
            if (!isNaN(v) && v > 0) sys.cpuTempMax = v / 1000;
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload();
            cpuInfoFile.reload();
            memFile.reload();
            if (shell.cpuTempPath !== "") cpuTempFile.reload();
            if (shell.igpuDir !== "") { rc6File.reload(); igpuFreqFile.reload(); igpuReqFile.reload(); }
        }
    }

    // ---- GPU: one long-lived nvidia-smi that streams a sample per second ---
    Process {
        id: gpuProc
        running: true
        command: ["nvidia-smi",
            "--query-gpu=utilization.gpu,clocks.sm,clocks.max.sm,memory.used,memory.total,temperature.gpu,power.draw,enforced.power.limit,clocks.mem",
            "--format=csv,noheader,nounits", "-l", "1"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const f = data.split(",").map(s => s.trim());
                if (f.length < 9) return;
                const num = s => { const v = parseFloat(s); return isNaN(v) ? 0 : v; };
                sys.gpuUtil = num(f[0]) / 100;
                sys.gpuClock = num(f[1]);
                sys.gpuClockMax = Math.max(1, num(f[2]));
                sys.vramUsed = num(f[3]) / 1024;
                sys.vramTotal = num(f[4]) / 1024;
                sys.gpuTemp = num(f[5]);
                sys.gpuPower = num(f[6]);
                sys.gpuPowerMax = num(f[7]);
                sys.gpuMemClock = num(f[8]);
                sys.gpuOk = true;
            }
        }
    }

    // ============================================================
    //  THE PANEL
    //
    //  Two surfaces on purpose: the scrim is fullscreen but never
    //  redraws once it has faded in, while the animated bubbles live
    //  in a much smaller window. Only the small one is recomposited
    //  every frame, which keeps the whole thing cheap.
    // ============================================================
    property bool closing: false

    function dismiss() {
        if (closing) return;
        closing = true;
        b0.dismiss(); b1.dismiss(); b2.dismiss(); b3.dismiss(); b4.dismiss(); b5.dismiss();
        quitTimer.start();
    }

    Timer { id: quitTimer; interval: 1100; onTriggered: Qt.quit() }

    // graceful close from the launcher:  qs -p <this file> ipc call sysmon close
    IpcHandler {
        target: "sysmon"
        function close(): void { shell.dismiss() }
    }

    PanelWindow {
        id: scrimWin
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-sysmonitor-scrim"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { top: true; bottom: true; left: true; right: true }

        Rectangle {
            id: scrim
            anchors.fill: parent
            color: Qt.rgba(pal.scrim.r, pal.scrim.g, pal.scrim.b, 1)
            opacity: 0
            Component.onCompleted: opacity = 0.55
            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutQuad } }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: shell.dismiss()
            }
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: shell.dismiss()
            Keys.onPressed: event => { if (event.key === Qt.Key_Q) shell.dismiss(); }
        }

        Connections {
            target: shell
            function onClosingChanged() { if (shell.closing) scrim.opacity = 0; }
        }
    }

    PanelWindow {
        id: win
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-sysmonitor"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // no anchors -> the compositor centres the surface
        implicitWidth: 1300
        implicitHeight: 800

        // clicks that miss a bubble still count as "outside"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: shell.dismiss()
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: -22

            // ---- CPU ----
            Item {
                width: 238; height: 260
                Bubble {
                    id: b0
                    pal: pal; index: 0; total: 6; diameter: 186; baseOffset: -30
                    label: "CPU"
                    value: sys.cpuUsage
                    readout: String(sys.pct(sys.cpuUsage))
                    unit: "%"
                    detail: (sys.cpuMhz / 1000).toFixed(2) + " GHz"
                    sub: sys.cpuThreads + " threads"
                }
            }

            // ---- RAM ----
            Item {
                width: 194; height: 260
                Bubble {
                    id: b1
                    pal: pal; index: 1; total: 6; diameter: 152; baseOffset: 46
                    label: "RAM"
                    value: sys.memTotal > 0 ? sys.memUsed / sys.memTotal : 0
                    readout: sys.memTotal > 0 ? String(sys.pct(sys.memUsed / sys.memTotal)) : "--"
                    unit: "%"
                    detail: sys.gib(sys.memUsed) + " / " + sys.gib(sys.memTotal) + " GiB"
                    sub: sys.gib(sys.memAvail) + " GiB free"
                }
            }

            // ---- integrated GPU ----
            Item {
                width: 194; height: 260
                Bubble {
                    id: b2
                    pal: pal; index: 2; total: 6; diameter: 152; baseOffset: -6
                    label: "iGPU"
                    value: sys.igpuBusy
                    readout: sys.igpuOk ? String(sys.pct(sys.igpuBusy)) : "--"
                    unit: "%"
                    detail: Math.round(sys.igpuFreq > 0 ? sys.igpuFreq : sys.igpuFreqReq) + " MHz"
                    sub: sys.igpuFreqMax > 0 ? "max " + Math.round(sys.igpuFreqMax) + " MHz" : ""
                }
            }

            // ---- discrete GPU ----
            Item {
                width: 238; height: 260
                Bubble {
                    id: b3
                    pal: pal; index: 3; total: 6; diameter: 186; baseOffset: -52
                    label: "GPU"
                    value: sys.gpuUtil
                    readout: sys.gpuOk ? String(sys.pct(sys.gpuUtil)) : "--"
                    unit: "%"
                    detail: sys.gpuOk ? Math.round(sys.gpuClock) + " MHz" : "not available"
                    sub: sys.gpuOk ? "max " + Math.round(sys.gpuClockMax) + " MHz" : ""
                }
            }

            // ---- VRAM ----
            Item {
                width: 194; height: 260
                Bubble {
                    id: b4
                    pal: pal; index: 4; total: 6; diameter: 152; baseOffset: 38
                    label: "VRAM"
                    value: sys.vramTotal > 0 ? sys.vramUsed / sys.vramTotal : 0
                    readout: sys.gpuOk && sys.vramTotal > 0 ? String(sys.pct(sys.vramUsed / sys.vramTotal)) : "--"
                    unit: "%"
                    detail: sys.gib(sys.vramUsed) + " / " + sys.gib(sys.vramTotal) + " GiB"
                    sub: sys.gpuOk ? Math.round(sys.gpuMemClock) + " MHz" : ""
                }
            }

            // ---- THERMALS ----
            Item {
                width: 238; height: 260
                Bubble {
                    id: b5
                    pal: pal; index: 5; total: 6; diameter: 186; baseOffset: -16
                    mode: "thermo"
                    label: "TEMP"
                    labelA: "CPU"
                    tempA: sys.cpuTemp
                    tempAMax: sys.cpuTempMax
                    labelB: "GPU"
                    tempB: sys.gpuTemp
                    tempBMax: 95
                    detail: sys.gpuOk ? sys.gpuPower.toFixed(1) + " W"
                                      + (sys.gpuPowerMax > 0 ? " / " + Math.round(sys.gpuPowerMax) + " W" : "")
                                      : ""
                }
            }
        }
    }
}
