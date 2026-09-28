import QtQuick
import qs.CustomTheme

// A scrolling history chart: gridlines with labels on the left, and one line
// per series with a light fill under it. The newest sample is on the right.
//
// Repaints only when `revision` changes, which the panel ties to the sampler's
// tick, so a chart costs nothing between samples.
Canvas {
    id: chart

    // [{ values: [...], color: <color> }, ...]
    property var series: []
    property int capacity: 60
    // The top of the scale. With autoScale it grows to the largest value on
    // screen (never below `maximum`), rounded to a tidy number.
    property real maximum: 100
    property bool autoScale: false
    // Turns an axis value into its label.
    property var format: v => Math.round(v)
    property int revision: 0
    // Off for small charts: no labels, and only the outer gridlines.
    property bool showAxis: true

    readonly property real scaleTop: {
        if (!chart.autoScale)
            return chart.maximum
        let m = chart.maximum
        for (const s of chart.series)
            for (const v of (s.values || []))
                if (v > m) m = v
        // 1, 2 or 5 times a power of ten: tidy numbers on the axis.
        const p = Math.pow(10, Math.floor(Math.log10(m)))
        for (const k of [1, 2, 2.5, 5, 10])
            if (k * p >= m) return k * p
        return m
    }

    implicitHeight: 90
    renderStrategy: Canvas.Cooperative

    onRevisionChanged: requestPaint()
    onScaleTopChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const labelW = chart.showAxis ? 50 : 0
        const x0 = labelW, y0 = chart.showAxis ? 5 : 1
        const w = width - x0 - 2, h = height - y0 - (chart.showAxis ? 6 : 1)
        if (w <= 0 || h <= 0)
            return

        // Gridlines at quarters, labelled on the left.
        ctx.font = "10px '" + Theme.fontFamily + "'"
        ctx.textAlign = "right"
        ctx.textBaseline = "middle"
        ctx.lineWidth = 1
        for (let i = 0; i <= 4; i++) {
            if (!chart.showAxis && i !== 0 && i !== 4)
                continue
            const y = Math.round(y0 + h * i / 4) + 0.5
            ctx.strokeStyle = Qt.alpha(Theme.on_background, 0.12)
            ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x0 + w, y); ctx.stroke()
            if (!chart.showAxis)
                continue
            ctx.fillStyle = Qt.alpha(Theme.on_background, 0.55)
            ctx.fillText(chart.format(chart.scaleTop * (4 - i) / 4), x0 - 6, y)
        }

        const step = w / Math.max(1, chart.capacity - 1)
        for (const s of chart.series) {
            const vals = s.values || []
            if (vals.length < 2)
                continue
            const start = x0 + w - (vals.length - 1) * step
            const yOf = v => y0 + h - Math.max(0, Math.min(1, v / chart.scaleTop)) * h

            ctx.beginPath()
            ctx.moveTo(start, yOf(vals[0]))
            for (let i = 1; i < vals.length; i++)
                ctx.lineTo(start + i * step, yOf(vals[i]))
            ctx.strokeStyle = s.color
            ctx.lineWidth = 1.6
            ctx.lineJoin = "round"
            ctx.stroke()

            ctx.lineTo(start + (vals.length - 1) * step, y0 + h)
            ctx.lineTo(start, y0 + h)
            ctx.closePath()
            ctx.fillStyle = Qt.alpha(s.color, 0.16)
            ctx.fill()
        }
    }
}
