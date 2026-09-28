//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQml

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
        zramSizeFile.reload();
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

        // false when the machine has no usable integrated GPU (e.g. a desktop
        // driving everything off the discrete card) -> the iGPU bubble is hidden
        property bool igpuPresent: false
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

        property var cores: []          // per-thread busy fraction, 0..1
        property real load1: 0
        property real load5: 0
        property real load15: 0

        property real zramUsed: 0       // GiB actually stored
        property real zramTotal: 0      // GiB of backing device
        property real zramRatio: 0      // compression ratio, 0 when not meaningful

        property var nvmeTemps: []      // °C, parallel to shell.nvmeDrives

        property bool netPresent: false
        property string netIface: ""
        property string netIp: ""
        property real netLinkMbit: 0
        property real netRx: 0          // bytes/s down
        property real netTx: 0          // bytes/s up
        property real netPeak: 1048576  // adaptive gauge full-scale, floored at 1 MB/s

        function pct(v) { return Math.round(Math.max(0, Math.min(1, v)) * 100); }
        function gib(v) { return v >= 10 ? v.toFixed(1) : v.toFixed(2); }

        // split so the bubble can render the number big and the unit small
        function rateNum(b) {
            if (b >= 1048576) return (b / 1048576).toFixed(1);
            if (b >= 1024) return String(Math.round(b / 1024));
            return String(Math.round(b));
        }
        function rateUnit(b) {
            if (b >= 1048576) return "MB/s";
            if (b >= 1024) return "KB/s";
            return "B/s";
        }
        function rate(b) { return rateNum(b) + " " + rateUnit(b); }
    }

    // ---- CPU: /proc/stat deltas -------------------------------------------
    property var prevCpu: null
    property var prevCores: ({})
    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const lines = text().split("\n");

            const line = lines[0].trim().split(/\s+/);
            let total = 0;
            for (let i = 1; i < line.length; i++) total += parseInt(line[i]) || 0;
            const idle = (parseInt(line[4]) || 0) + (parseInt(line[5]) || 0);
            if (shell.prevCpu) {
                const dt = total - shell.prevCpu.total;
                const di = idle - shell.prevCpu.idle;
                if (dt > 0) sys.cpuUsage = Math.max(0, Math.min(1, 1 - di / dt));
            }
            shell.prevCpu = { total: total, idle: idle };

            // the "cpuN" lines feed the per-core panel; tracked every tick so
            // the bars are already populated the moment the panel is opened
            const cur = {};
            const busy = [];
            for (const ln of lines) {
                const m = ln.match(/^cpu(\d+)\s+(.*)$/);
                if (!m) continue;
                const n = parseInt(m[1]);
                const f = m[2].trim().split(/\s+/).map(x => parseInt(x) || 0);
                let ct = 0;
                for (const v of f) ct += v;
                const ci = (f[3] || 0) + (f[4] || 0);
                cur[n] = { total: ct, idle: ci };
                const prev = shell.prevCores[n];
                const dt2 = prev ? ct - prev.total : 0;
                busy[n] = dt2 > 0
                    ? Math.max(0, Math.min(1, 1 - (ci - prev.idle) / dt2))
                    : 0;
            }
            shell.prevCores = cur;
            sys.cores = busy;
        }
    }

    // ---- load average: a truer "is this box struggling" signal than the
    //      instantaneous percentage, which any 1 s sample flatters ----------
    FileView {
        id: loadFile
        path: "/proc/loadavg"
        printErrors: false
        onLoaded: {
            const f = text().trim().split(/\s+/);
            sys.load1 = parseFloat(f[0]) || 0;
            sys.load5 = parseFloat(f[1]) || 0;
            sys.load15 = parseFloat(f[2]) || 0;
        }
    }

    // ---- zram: compressed swap fills long before the machine starts to
    //      thrash, so it is the early warning the RAM gauge cannot give -----
    property real zramDisksize: 0
    FileView {
        id: zramSizeFile
        path: "/sys/block/zram0/disksize"
        printErrors: false
        onLoaded: {
            const v = parseFloat(text());
            if (!isNaN(v)) sys.zramTotal = v / 1073741824;
        }
    }
    FileView {
        id: zramStatFile
        path: "/sys/block/zram0/mm_stat"
        printErrors: false
        onLoaded: {
            // orig_data_size compr_data_size mem_used_total ...
            const f = text().trim().split(/\s+/).map(x => parseFloat(x) || 0);
            sys.zramUsed = f[0] / 1073741824;
            // a ratio computed over a few KiB is noise, not information
            sys.zramRatio = (f[0] > 16777216 && f[1] > 0) ? f[0] / f[1] : 0;
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
    //      A card only counts as an iGPU if its driver is one of the integrated
    //      ones *and* it exposes the RC6/frequency sysfs we read below; a box
    //      that renders solely on the discrete card has no such node, so the
    //      bubble is dropped from the row entirely.
    Process {
        running: true
        command: ["bash", "-c",
            "for c in /sys/class/drm/card[0-9]*; do " +
            "  case \"${c##*/}\" in *-*) continue;; esac; " +
            "  drv=$(basename \"$(readlink -f \"$c/device/driver\" 2>/dev/null)\" 2>/dev/null); " +
            "  case \"$drv\" in i915|xe) ;; *) continue;; esac; " +
            "  [ -r \"$c/power/rc6_residency_ms\" ] && { echo \"$c\"; exit 0; }; " +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const dir = this.text.trim();
                if (dir === "") {
                    sys.igpuPresent = false;
                    return;
                }
                igpuMaxFile.path = dir + "/gt_max_freq_mhz";
                igpuFreqFile.path = dir + "/gt_act_freq_mhz";
                igpuReqFile.path = dir + "/gt_cur_freq_mhz";
                shell.igpuDir = dir + "/power/rc6_residency_ms";
                sys.igpuPresent = true;
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
            loadFile.reload();
            zramStatFile.reload();
            if (shell.cpuTempPath !== "") cpuTempFile.reload();
            if (shell.igpuDir !== "") { rc6File.reload(); igpuFreqFile.reload(); igpuReqFile.reload(); }
            for (let i = 0; i < nvmeViews.count; i++) nvmeViews.objectAt(i).reload();
            if (sys.netPresent) { rxFile.reload(); txFile.reload(); }
        }
    }

    // ---- NVMe drive temperatures: every nvme hwmon exposes a Composite
    //      sensor, and the drives throttle long before anything else here
    //      does, so they earn a place next to the CPU and GPU ---------------
    property var nvmeDrives: []
    Process {
        running: true
        command: ["bash", "-c",
            "i=0; for h in /sys/class/hwmon/*; do " +
            "  [ \"$(cat \"$h/name\" 2>/dev/null)\" = nvme ] || continue; " +
            "  [ -r \"$h/temp1_input\" ] || continue; " +
            "  d=$(basename \"$(readlink -f \"$h/device\" 2>/dev/null)\" 2>/dev/null); " +
            "  c=$(cat \"$h/temp1_crit\" 2>/dev/null || cat \"$h/temp1_max\" 2>/dev/null || echo 85000); " +
            "  echo \"$h/temp1_input|$d|$c\"; " +
            "  i=$((i+1)); [ $i -ge 4 ] && break; " +
            "done | sort -t'|' -k2"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text.trim();
                if (out === "") return;
                const drives = [];
                const lines = out.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const f = lines[i].split("|");
                    if (f.length < 3) continue;
                    drives.push({
                        path: f[0],
                        // "SSD" alone when there is only one, numbered otherwise
                        label: lines.length === 1 ? "SSD" : "SSD" + i,
                        max: Math.round((parseFloat(f[2]) || 85000) / 1000)
                    });
                }
                shell.nvmeDrives = drives;
            }
        }
    }

    Instantiator {
        id: nvmeViews
        model: shell.nvmeDrives
        delegate: FileView {
            required property var modelData
            required property int index
            path: modelData.path
            printErrors: false
            onLoaded: {
                const v = parseFloat(text());
                if (isNaN(v)) return;
                // reassign rather than mutate: QML only notifies on the write
                const a = sys.nvmeTemps.slice();
                a[index] = v / 1000;
                sys.nvmeTemps = a;
            }
        }
    }

    // ---- network: whichever interface actually carries the default route,
    //      so a box full of docker/virbr bridges still reports the real one --
    Process {
        running: true
        command: ["bash", "-c",
            "set -- $(ip -o -4 route show default 2>/dev/null | head -1); " +
            "dev=; src=; " +
            "while [ $# -gt 0 ]; do case \"$1\" in " +
            "  dev) dev=$2; shift;; src) src=$2; shift;; esac; shift; done; " +
            "if [ -z \"$dev\" ]; then " +
            "  for i in /sys/class/net/*; do n=${i##*/}; " +
            "    case \"$n\" in lo|docker*|br-*|veth*|virbr*|tun*|tap*) continue;; esac; " +
            "    [ \"$(cat \"$i/operstate\" 2>/dev/null)\" = up ] && { dev=$n; break; }; " +
            "  done; " +
            "fi; " +
            "[ -n \"$dev\" ] || exit 0; " +
            "[ -n \"$src\" ] || src=$(ip -o -4 addr show dev \"$dev\" 2>/dev/null " +
            "  | awk \'{print $4}\' | cut -d/ -f1 | head -1); " +
            "spd=$(cat \"/sys/class/net/$dev/speed\" 2>/dev/null); " +
            "case \"$spd\" in \'\'|*[!0-9]*) spd=0;; esac; " +
            "echo \"$dev|$src|$spd\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = this.text.trim().split("|");
                if (f.length < 3 || f[0] === "") {
                    sys.netPresent = false;
                    return;
                }
                sys.netIface = f[0];
                sys.netIp = f[1];
                sys.netLinkMbit = parseFloat(f[2]) || 0;
                rxFile.path = "/sys/class/net/" + f[0] + "/statistics/rx_bytes";
                txFile.path = "/sys/class/net/" + f[0] + "/statistics/tx_bytes";
                sys.netPresent = true;
                // take a second sample quickly: byte counters are useless until
                // there are two of them, and this panel is only up for seconds
                netPrimeTimer.start();
            }
        }
    }

    property real prevRx: -1
    property real prevTx: -1
    property real prevNetAt: 0

    Timer {
        id: netPrimeTimer
        interval: 350
        repeat: false
        onTriggered: { rxFile.reload(); txFile.reload(); }
    }

    function netSample(rx, tx) {
        const now = Date.now();
        if (shell.prevRx >= 0 && shell.prevTx >= 0) {
            const dt = (now - shell.prevNetAt) / 1000;
            // counters wrap / reset on interface changes: ignore a negative delta
            if (dt > 0.05 && rx >= shell.prevRx && tx >= shell.prevTx) {
                sys.netRx = (rx - shell.prevRx) / dt;
                sys.netTx = (tx - shell.prevTx) / dt;
                sys.netPeak = Math.max(sys.netPeak, sys.netRx);
            }
        }
        shell.prevRx = rx;
        shell.prevTx = tx;
        shell.prevNetAt = now;
    }

    // both counters are read in the same tick; the second one to land samples
    property real pendingRx: -1
    FileView {
        id: rxFile
        printErrors: false
        onLoaded: { shell.pendingRx = parseFloat(text()) || 0; }
    }
    FileView {
        id: txFile
        printErrors: false
        onLoaded: {
            const tx = parseFloat(text()) || 0;
            if (shell.pendingRx >= 0) shell.netSample(shell.pendingRx, tx);
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
    // ============================================================
    property bool closing: false

    // Bubbles for hardware the machine does not have are dropped from the row,
    // so the stagger order has to be computed rather than hard-coded.
    // Slots: 0 CPU  1 RAM  2 iGPU  3 GPU  4 VRAM  5 NET  6 TEMP
    readonly property var hiddenSlots: {
        const h = [];
        if (!sys.igpuPresent) h.push(2);
        if (!sys.netPresent) h.push(5);
        return h;
    }
    readonly property int bubbleCount: 7 - hiddenSlots.length
    function bubbleIndex(slot) {
        let before = 0;
        for (const s of hiddenSlots) if (s < slot) before++;
        return slot - before;
    }

    // the per-core panel is a second layer over the row, not a seventh bubble
    property bool coresOpen: false

    // opened by dwelling on the CPU bubble, so it closes again once the
    // pointer has left both it and the panel -- with a grace period, since
    // crossing the gap between them passes over neither
    readonly property bool coreHovered: b0.hovered || corePanel.cardHovered
    onCoreHoveredChanged: {
        if (coreHovered) coreCloseTimer.stop();
        else if (coresOpen) coreCloseTimer.restart();
    }
    Timer {
        id: coreCloseTimer
        interval: 600
        onTriggered: shell.coresOpen = false
    }

    function dismiss() {
        if (closing) return;
        closing = true;
        b0.dismiss(); b1.dismiss();
        if (sys.igpuPresent) b2.dismiss();
        b3.dismiss(); b4.dismiss();
        if (sys.netPresent) b5.dismiss();
        b6.dismiss();
        quitTimer.start();
    }

    Timer { id: quitTimer; interval: 1100; onTriggered: Qt.quit() }

    // graceful close from the launcher:  qs -p <this file> ipc call sysmon close
    IpcHandler {
        target: "sysmon"
        function close(): void { shell.dismiss() }
    }

    // ============================================================
    //  THE PANEL
    //
    //  One fullscreen surface, not two.
    //
    //  The scrim and the bubbles used to live in separate layer-shell
    //  windows so only the small one was recomposited each frame. That
    //  cannot work once the bubbles need the pointer: whichever surface
    //  holds WlrKeyboardFocus.Exclusive captures *all* pointer input
    //  under Hyprland, so the bubbles never saw a hover or a click, and
    //  every click reached the scrim's dismiss handler instead -- which
    //  is exactly why clicking the CPU bubble quit the app. An input
    //  mask does not help; the grab wins over the input region.
    // ============================================================
    PanelWindow {
        id: win
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-sysmonitor"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { top: true; bottom: true; left: true; right: true }

        Rectangle {
            id: scrim
            anchors.fill: parent
            color: Qt.rgba(pal.scrim.r, pal.scrim.g, pal.scrim.b, 1)
            opacity: 0
            Component.onCompleted: opacity = 0.55
            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutQuad } }
        }

        Connections {
            target: shell
            function onClosingChanged() { if (shell.closing) scrim.opacity = 0; }
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: {
                if (shell.coresOpen) shell.coresOpen = false;
                else shell.dismiss();
            }
            Keys.onPressed: event => { if (event.key === Qt.Key_Q) shell.dismiss(); }
        }

        // clicks that miss a bubble still count as "outside"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: {
                if (shell.coresOpen) shell.coresOpen = false;
                else shell.dismiss();
            }
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: -24


            // ---- CPU ----
            Item {
                width: 264; height: 288
                Bubble {
                    id: b0
                    pal: pal; index: shell.bubbleIndex(0); total: shell.bubbleCount; diameter: 206; baseOffset: -33
                    label: "CPU"
                    value: sys.cpuUsage
                    readout: String(sys.pct(sys.cpuUsage))
                    unit: "%"
                    detail: (sys.cpuMhz / 1000).toFixed(2) + " GHz"
                    sub: sys.cpuThreads + " threads"
                    sub2: "load " + sys.load1.toFixed(2) + " · " + sys.load5.toFixed(2)
                                  + " · " + sys.load15.toFixed(2)
                    interactive: true
                    dwellMs: 500
                    onDwelled: shell.coresOpen = true
                    onClicked: shell.coresOpen = true
                }
            }

            // ---- RAM ----
            Item {
                width: 215; height: 288
                Bubble {
                    id: b1
                    pal: pal; index: shell.bubbleIndex(1); total: shell.bubbleCount; diameter: 168; baseOffset: 51
                    label: "RAM"
                    value: sys.memTotal > 0 ? sys.memUsed / sys.memTotal : 0
                    readout: sys.memTotal > 0 ? String(sys.pct(sys.memUsed / sys.memTotal)) : "--"
                    unit: "%"
                    detail: sys.gib(sys.memUsed) + " / " + sys.gib(sys.memTotal) + " GiB"
                    sub: sys.gib(sys.memAvail) + " GiB free"
                    sub2: sys.zramTotal > 0
                          ? "zram " + sys.gib(sys.zramUsed) + " / " + sys.gib(sys.zramTotal)
                            + (sys.zramRatio > 0 ? " · " + sys.zramRatio.toFixed(1) + "x" : "")
                          : ""
                }
            }

            // ---- integrated GPU (only on machines that actually have one) ----
            Item {
                visible: sys.igpuPresent
                width: visible ? 215 : 0; height: 288
                Bubble {
                    id: b2
                    pal: pal; index: shell.bubbleIndex(2); total: shell.bubbleCount; diameter: 168; baseOffset: -7
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
                width: 264; height: 288
                Bubble {
                    id: b3
                    pal: pal; index: shell.bubbleIndex(3); total: shell.bubbleCount; diameter: 206; baseOffset: -57
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
                width: 215; height: 288
                Bubble {
                    id: b4
                    pal: pal; index: shell.bubbleIndex(4); total: shell.bubbleCount; diameter: 168; baseOffset: 42
                    label: "VRAM"
                    value: sys.vramTotal > 0 ? sys.vramUsed / sys.vramTotal : 0
                    readout: sys.gpuOk && sys.vramTotal > 0 ? String(sys.pct(sys.vramUsed / sys.vramTotal)) : "--"
                    unit: "%"
                    detail: sys.gib(sys.vramUsed) + " / " + sys.gib(sys.vramTotal) + " GiB"
                    sub: sys.gpuOk ? Math.round(sys.gpuMemClock) + " MHz" : ""
                }
            }

            // ---- NETWORK (only when an interface carries the default route) ----
            Item {
                visible: sys.netPresent
                width: visible ? 215 : 0; height: 288
                Bubble {
                    id: b5
                    pal: pal; index: shell.bubbleIndex(5); total: shell.bubbleCount
                    diameter: 168; baseOffset: 33
                    label: "NET"
                    // no honest fixed full-scale for throughput, so the gauge
                    // tracks the fastest rate seen since launch (min 1 MB/s)
                    value: sys.netRx / sys.netPeak
                    readout: sys.rateNum(sys.netRx)
                    unit: sys.rateUnit(sys.netRx)
                    detail: "↑ " + sys.rate(sys.netTx)
                    sub: sys.netIp
                    sub2: sys.netIface
                          + (sys.netLinkMbit > 0
                             ? " · " + (sys.netLinkMbit >= 1000
                                        ? (sys.netLinkMbit / 1000) + " Gb/s"
                                        : sys.netLinkMbit + " Mb/s")
                             : "")
                }
            }

            // ---- THERMALS ----
            Item {
                width: 264; height: 288
                Bubble {
                    id: b6
                    pal: pal; index: shell.bubbleIndex(6); total: shell.bubbleCount; diameter: 206; baseOffset: -18
                    mode: "thermo"
                    label: "TEMP"
                    probes: {
                        const p = [{ label: "CPU", temp: sys.cpuTemp, max: sys.cpuTempMax }];
                        if (sys.gpuOk) p.push({ label: "GPU", temp: sys.gpuTemp, max: 95 });
                        // three drives is where the thermometers stop being legible
                        const drives = shell.nvmeDrives;
                        for (let i = 0; i < Math.min(3, drives.length); i++)
                            p.push({ label: drives[i].label,
                                     temp: sys.nvmeTemps[i] || 0,
                                     max: drives[i].max });
                        return p;
                    }
                    detail: sys.gpuOk ? sys.gpuPower.toFixed(1) + " W"
                                      + (sys.gpuPowerMax > 0 ? " / " + Math.round(sys.gpuPowerMax) + " W" : "")
                                      : ""
                }
            }
        }

        CorePanel {
            id: corePanel
            anchors.fill: parent
            pal: pal
            cores: sys.cores
            open: shell.coresOpen
            onCloseRequested: shell.coresOpen = false
            // parked just left of the row, next to the CPU bubble that opens it
            cardRightEdge: row.x - 36
        }
    }
}
