import Quickshell
import Quickshell.Io
import QtQuick

// Everything the system panel shows, sampled once a second while `active`.
//
// Nothing runs while the panel is closed: no timer, no nvidia-smi, no reads.
// The charts start from the moment the panel opens, and are cleared when it
// closes, so no history is kept in the background either.
//
// The sources are the ones the SysMonitor app uses (/proc, sysfs, nvidia-smi),
// so the two always agree.
Item {
    id: stats

    property bool active: false

    // Samples kept per chart: one a second, so a minute of history.
    readonly property int historyLength: 60
    // Bumped after every sample, so the charts know to repaint.
    property int tick: 0

    // ------------------------------------------------------------------
    // VALUES
    // ------------------------------------------------------------------
    property string cpuName: ""
    property real cpuUsage: 0            // 0..1
    property real cpuTemp: 0             // °C
    property var cores: []               // per thread, 0..1
    property var cpuHist: []
    property var cpuTempHist: []
    property var coreHist: []            // one history per thread

    property real memTotal: 0            // GiB
    property real memUsed: 0
    property real swapTotal: 0
    property real swapUsed: 0

    // "nvidia", "igpu" or "" when neither is there.
    property string gpuKind: ""
    property string gpuName: ""
    property real gpuUtil: 0             // 0..1
    property real gpuTemp: 0
    property real gpuPower: 0            // W
    property real gpuPowerMax: 0
    property real vramUsed: 0            // GiB
    property real vramTotal: 0
    property real gpuFreq: 0             // MHz (iGPU)
    property real gpuFreqMax: 0
    property var gpuUtilHist: []
    property var gpuTempHist: []
    property var gpuPowerHist: []
    property var vramHist: []
    property var gpuFreqHist: []

    property string netIface: ""
    property real netRx: 0               // bytes/s
    property real netTx: 0
    property var netRxHist: []
    property var netTxHist: []

    // Mounted filesystems, one per device: { label, used, size } in bytes.
    property var filesystems: []
    // Physical drives with something mounted on them: { name, label }.
    property var drives: []
    // Bytes/s written, per drive name, and its history.
    property var driveWrite: ({})
    property var driveWriteHist: ({})

    function push(list, v) {
        const a = list.slice(Math.max(0, list.length - stats.historyLength + 1))
        a.push(v)
        return a
    }

    // Called on closing: the next opening starts with empty charts, and the
    // first rates are measured afresh instead of across the closed gap.
    function clearHistory(): void {
        stats.cpuHist = []; stats.cpuTempHist = []; stats.coreHist = []
        stats.gpuUtilHist = []; stats.gpuTempHist = []; stats.gpuPowerHist = []
        stats.vramHist = []; stats.gpuFreqHist = []
        stats.netRxHist = []; stats.netTxHist = []
        stats.driveWriteHist = ({})
        stats.prevCpu = null; stats.prevCores = ({})
        stats.prevRx = -1; stats.prevTx = -1; stats.prevSectors = ({}); stats.prevRc6 = -1
        stats.cpuUsage = 0; stats.gpuUtil = 0; stats.netRx = 0; stats.netTx = 0
        stats.driveWrite = ({})
        stats.tick++
    }

    function gib(v) { return v >= 10 ? v.toFixed(1) : v.toFixed(2) }

    function rate(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GiB/s"
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MiB/s"
        if (b >= 1024) return Math.round(b / 1024) + " KiB/s"
        return Math.round(b) + " B/s"
    }

    function size(b) {
        if (b >= 1099511627776) return (b / 1099511627776).toFixed(1) + " TiB"
        if (b >= 1073741824) return (b / 1073741824).toFixed(0) + " GiB"
        return (b / 1048576).toFixed(0) + " MiB"
    }

    // ------------------------------------------------------------------
    // SAMPLING
    // ------------------------------------------------------------------
    Timer {
        interval: 1000
        repeat: true
        running: stats.active
        triggeredOnStart: true
        onTriggered: {
            statFile.reload()
            memFile.reload()
            diskstatsFile.reload()
            if (stats.cpuTempPath !== "") cpuTempFile.reload()
            if (stats.gpuKind === "igpu") { rc6File.reload(); igpuFreqFile.reload() }
            if (stats.netIface !== "") { rxFile.reload(); txFile.reload() }
            // Appended a moment later, once the reads above have landed.
            recordTimer.restart()
        }
    }

    Timer {
        id: recordTimer
        interval: 150
        onTriggered: {
            stats.cpuHist = stats.push(stats.cpuHist, stats.cpuUsage)
            stats.cpuTempHist = stats.push(stats.cpuTempHist, stats.cpuTemp)
            stats.coreHist = stats.cores.map((v, i) => stats.push(stats.coreHist[i] || [], v))
            stats.netRxHist = stats.push(stats.netRxHist, stats.netRx)
            stats.netTxHist = stats.push(stats.netTxHist, stats.netTx)
            if (stats.gpuKind !== "") {
                stats.gpuUtilHist = stats.push(stats.gpuUtilHist, stats.gpuUtil)
                stats.gpuTempHist = stats.push(stats.gpuTempHist, stats.gpuTemp)
                stats.gpuPowerHist = stats.push(stats.gpuPowerHist, stats.gpuPower)
                stats.vramHist = stats.push(stats.vramHist, stats.vramUsed)
                stats.gpuFreqHist = stats.push(stats.gpuFreqHist, stats.gpuFreq)
            }
            let h = ({})
            for (const d of stats.drives)
                h[d.name] = stats.push(stats.driveWriteHist[d.name] || [], stats.driveWrite[d.name] || 0)
            stats.driveWriteHist = h
            stats.tick++
        }
    }

    // Disk usage barely moves, so it is read on opening and every 15 s.
    Timer {
        interval: 15000
        repeat: true
        running: stats.active
        triggeredOnStart: true
        onTriggered: { dfProc.running = false; dfProc.running = true }
    }

    // What the machine has is looked up once, the first time the panel opens.
    // The drive list is looked up on every opening: a disk may have been
    // mounted since.
    property bool probed: false
    onActiveChanged: {
        if (!stats.active) {
            stats.clearHistory()
            return
        }
        lsblkProc.running = false
        lsblkProc.running = true
        if (stats.probed)
            return
        stats.probed = true
        cpuInfoFile.reload()
        probeProc.running = true
        netProc.running = true
    }

    // ------------------------------------------------------------------
    // CPU
    // ------------------------------------------------------------------
    FileView {
        id: cpuInfoFile
        path: "/proc/cpuinfo"
        printErrors: false
        onLoaded: {
            const m = text().match(/model name\s*:\s*(.*)/)
            if (!m)
                return
            // "Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz" -> "Intel Core i7-9700K"
            // "AMD Ryzen 7 8700G w/ Radeon 780M Graphics" -> "AMD Ryzen 7 8700G"
            stats.cpuName = m[1].replace(/\((R|TM|tm|r)\)/g, "")
                .replace(/\s+CPU\s+@.*$/, "").replace(/\s+@.*$/, "")
                .replace(/\s+w\/.*$/, "").replace(/\s+\d+-Core Processor.*$/, "")
                .replace(/\s+Processor$/, "").replace(/\s+/g, " ").trim()
        }
    }

    property var prevCpu: null
    property var prevCores: ({})
    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const lines = text().split("\n")
            const f0 = lines[0].trim().split(/\s+/)
            let total = 0
            for (let i = 1; i < f0.length; i++) total += parseInt(f0[i]) || 0
            const idle = (parseInt(f0[4]) || 0) + (parseInt(f0[5]) || 0)
            if (stats.prevCpu && total > stats.prevCpu.total)
                stats.cpuUsage = Math.max(0, Math.min(1,
                    1 - (idle - stats.prevCpu.idle) / (total - stats.prevCpu.total)))
            stats.prevCpu = { total: total, idle: idle }

            const cur = ({})
            const busy = []
            for (const ln of lines) {
                const m = ln.match(/^cpu(\d+)\s+(.*)$/)
                if (!m)
                    continue
                const n = parseInt(m[1])
                const f = m[2].trim().split(/\s+/).map(x => parseInt(x) || 0)
                let t = 0
                for (const v of f) t += v
                const id = (f[3] || 0) + (f[4] || 0)
                cur[n] = { total: t, idle: id }
                const p = stats.prevCores[n]
                busy[n] = (p && t > p.total)
                    ? Math.max(0, Math.min(1, 1 - (id - p.idle) / (t - p.total))) : 0
            }
            stats.prevCores = cur
            stats.cores = busy
        }
    }

    property string cpuTempPath: ""
    FileView {
        id: cpuTempFile
        path: stats.cpuTempPath
        printErrors: false
        onLoaded: {
            const v = parseFloat(text())
            if (!isNaN(v)) stats.cpuTemp = v / 1000
        }
    }

    // ------------------------------------------------------------------
    // MEMORY
    // ------------------------------------------------------------------
    FileView {
        id: memFile
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            const t = text()
            const kb = k => parseInt((t.match(new RegExp(k + ":\\s*(\\d+)")) || [0, 0])[1])
            stats.memTotal = kb("MemTotal") / 1048576
            stats.memUsed = (kb("MemTotal") - kb("MemAvailable")) / 1048576
            stats.swapTotal = kb("SwapTotal") / 1048576
            stats.swapUsed = (kb("SwapTotal") - kb("SwapFree")) / 1048576
        }
    }

    // ------------------------------------------------------------------
    // HARDWARE PROBE: CPU temperature sensor, and which GPU there is
    // ------------------------------------------------------------------
    // The same rules as SysMonitor: the first CPU package sensor; NVIDIA when
    // nvidia-smi can see a card, otherwise an Intel iGPU exposing RC6.
    Process {
        id: probeProc
        command: ["bash", "-c",
            "t=; for h in /sys/class/hwmon/*; do n=$(cat \"$h/name\" 2>/dev/null); " +
            "  case \"$n\" in coretemp|k10temp|zenpower|cpu_thermal|acpitz) " +
            "    [ -r \"$h/temp1_input\" ] && { t=$h/temp1_input; break; };; esac; done; " +
            "g=; if command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; then g=nvidia; " +
            "else for c in /sys/class/drm/card[0-9]*; do case \"${c##*/}\" in *-*) continue;; esac; " +
            "  drv=$(basename \"$(readlink -f \"$c/device/driver\" 2>/dev/null)\"); " +
            "  case \"$drv\" in i915|xe) ;; *) continue;; esac; " +
            "  [ -r \"$c/power/rc6_residency_ms\" ] && { g=igpu:$c; break; }; done; fi; " +
            "echo \"$t|$g\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = this.text.trim().split("|")
                stats.cpuTempPath = f[0] || ""
                const g = f[1] || ""
                if (g === "nvidia") {
                    stats.gpuKind = "nvidia"
                } else if (g.startsWith("igpu:")) {
                    const dir = g.substring(5)
                    rc6File.path = dir + "/power/rc6_residency_ms"
                    igpuFreqFile.path = dir + "/gt_act_freq_mhz"
                    igpuMaxFile.path = dir + "/gt_max_freq_mhz"
                    igpuMaxFile.reload()
                    stats.gpuName = "Integrated GPU"
                    stats.gpuKind = "igpu"
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // GPU: NVIDIA
    // ------------------------------------------------------------------
    // One long-lived nvidia-smi streaming a line a second, only while open.
    Process {
        running: stats.active && stats.gpuKind === "nvidia"
        command: ["nvidia-smi",
            "--query-gpu=name,utilization.gpu,temperature.gpu,power.draw,enforced.power.limit,memory.used,memory.total",
            "--format=csv,noheader,nounits", "-l", "1"]
        stdout: SplitParser {
            onRead: data => {
                const f = data.split(",").map(s => s.trim())
                if (f.length < 7)
                    return
                const num = s => { const v = parseFloat(s); return isNaN(v) ? 0 : v }
                stats.gpuName = f[0].replace(/^NVIDIA\s+/, "")
                stats.gpuUtil = num(f[1]) / 100
                stats.gpuTemp = num(f[2])
                stats.gpuPower = num(f[3])
                stats.gpuPowerMax = num(f[4])
                stats.vramUsed = num(f[5]) / 1024
                stats.vramTotal = num(f[6]) / 1024
            }
        }
    }

    // ------------------------------------------------------------------
    // GPU: Intel iGPU (RC6 residency = time spent idle)
    // ------------------------------------------------------------------
    property real prevRc6: -1
    property real prevRc6At: 0
    FileView {
        id: rc6File
        printErrors: false
        onLoaded: {
            const ms = parseFloat(text())
            const now = Date.now()
            if (isNaN(ms))
                return
            if (stats.prevRc6 >= 0 && now > stats.prevRc6At)
                stats.gpuUtil = Math.max(0, Math.min(1,
                    1 - (ms - stats.prevRc6) / (now - stats.prevRc6At)))
            stats.prevRc6 = ms
            stats.prevRc6At = now
        }
    }
    FileView {
        id: igpuFreqFile
        printErrors: false
        onLoaded: { const v = parseFloat(text()); if (!isNaN(v)) stats.gpuFreq = v }
    }
    FileView {
        id: igpuMaxFile
        printErrors: false
        onLoaded: { const v = parseFloat(text()); if (!isNaN(v)) stats.gpuFreqMax = v }
    }

    // ------------------------------------------------------------------
    // NETWORK: the interface carrying the default route
    // ------------------------------------------------------------------
    Process {
        id: netProc
        command: ["bash", "-c",
            "set -- $(ip -o -4 route show default 2>/dev/null | head -1); " +
            "while [ $# -gt 0 ]; do [ \"$1\" = dev ] && { echo \"$2\"; exit 0; }; shift; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const dev = this.text.trim()
                if (dev === "")
                    return
                rxFile.path = "/sys/class/net/" + dev + "/statistics/rx_bytes"
                txFile.path = "/sys/class/net/" + dev + "/statistics/tx_bytes"
                stats.netIface = dev
            }
        }
    }

    property real prevRx: -1
    property real prevTx: -1
    property real prevNetAt: 0
    property real pendingRx: -1
    FileView {
        id: rxFile
        printErrors: false
        onLoaded: stats.pendingRx = parseFloat(text()) || 0
    }
    FileView {
        id: txFile
        printErrors: false
        onLoaded: {
            const rx = stats.pendingRx
            const tx = parseFloat(text()) || 0
            const now = Date.now()
            const dt = (now - stats.prevNetAt) / 1000
            // A gap longer than a few ticks is the panel having been closed:
            // that delta is a total, not a rate, so it is skipped.
            if (stats.prevRx >= 0 && dt > 0.05 && dt < 5 && rx >= stats.prevRx && tx >= stats.prevTx) {
                stats.netRx = (rx - stats.prevRx) / dt
                stats.netTx = (tx - stats.prevTx) / dt
            }
            stats.prevRx = rx
            stats.prevTx = tx
            stats.prevNetAt = now
        }
    }

    // ------------------------------------------------------------------
    // DISKS
    // ------------------------------------------------------------------
    // Label for a mount point: "/" is ROOT, anything else its last part.
    function mountLabel(m: string): string {
        if (m === "/")
            return "ROOT"
        if (m === "/home")
            return "HOME"
        const parts = m.split("/").filter(p => p !== "")
        return parts.length > 0 ? parts[parts.length - 1] : m
    }

    // One row per filesystem: btrfs subvolumes mounted in several places
    // (/, /home, /var/log...) share a device and are only listed once, under
    // their shortest mount point.
    Process {
        id: dfProc
        command: ["df", "-B1", "--output=source,size,used,target",
                  "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "overlay",
                  "-x", "squashfs", "-x", "ramfs", "-x", "fuse.portal"]
        stdout: StdioCollector {
            onStreamFinished: {
                const bySource = ({})
                const order = []
                const lines = this.text.trim().split("\n").slice(1)
                for (const ln of lines) {
                    const m = ln.match(/^(\S+)\s+(\d+)\s+(\d+)\s+(.+)$/)
                    if (!m)
                        continue
                    const src = m[1], target = m[4]
                    const size = parseFloat(m[2]), used = parseFloat(m[3])
                    if (size <= 0)
                        continue
                    if (bySource[src] === undefined) {
                        bySource[src] = { label: stats.mountLabel(target), mount: target,
                                          used: used, size: size }
                        order.push(src)
                    } else if (target.length < bySource[src].mount.length) {
                        bySource[src].mount = target
                        bySource[src].label = stats.mountLabel(target)
                    }
                }
                stats.filesystems = order.map(s => bySource[s])
            }
        }
    }

    // Which physical drives to chart, named after what is mounted on them.
    // Found through lsblk because a mount can sit behind a partition, LUKS
    // and LVM before it reaches the disk.
    Process {
        id: lsblkProc
        command: ["lsblk", "-J", "-o", "NAME,TYPE,MODEL,MOUNTPOINTS"]
        stdout: StdioCollector {
            onStreamFinished: {
                let tree
                try { tree = JSON.parse(this.text) } catch (e) { return }
                const mountsUnder = node => {
                    let out = (node.mountpoints || []).filter(m => m && m !== "[SWAP]")
                    for (const c of (node.children || []))
                        out = out.concat(mountsUnder(c))
                    return out
                }
                const drives = []
                for (const d of (tree.blockdevices || [])) {
                    if (d.type !== "disk" || /^(zram|loop|ram)/.test(d.name))
                        continue
                    const mounts = mountsUnder(d)
                    if (mounts.length === 0)
                        continue
                    mounts.sort((a, b) => a.length - b.length)
                    drives.push({ name: d.name, label: stats.mountLabel(mounts[0]),
                                  model: (d.model || "").trim() })
                }
                stats.drives = drives
            }
        }
    }

    property var prevSectors: ({})
    property real prevDiskAt: 0
    FileView {
        id: diskstatsFile
        path: "/proc/diskstats"
        printErrors: false
        onLoaded: {
            const now = Date.now()
            const dt = (now - stats.prevDiskAt) / 1000
            const cur = ({})
            const rates = ({})
            for (const ln of text().split("\n")) {
                const f = ln.trim().split(/\s+/)
                if (f.length < 10)
                    continue
                // Field 9 (0-based) is sectors written; a sector here is
                // always 512 bytes, whatever the drive's own sector size.
                const name = f[2]
                const w = parseFloat(f[9]) || 0
                cur[name] = w
                const p = stats.prevSectors[name]
                rates[name] = (p !== undefined && dt > 0.05 && dt < 5 && w >= p)
                    ? (w - p) * 512 / dt : 0
            }
            stats.prevSectors = cur
            stats.prevDiskAt = now
            stats.driveWrite = rates
        }
    }
}
