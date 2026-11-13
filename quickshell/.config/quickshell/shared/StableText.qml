import QtQuick
import QtQuick.Layouts

// Text whose width does not move when its value does, for the bar's numbers.
//
// Digits are drawn tabular (every digit as wide as every other, the OpenType
// "tnum" feature), and the item is always at least as wide as `reserve`, the
// widest value it is expected to show — "100%" for a percentage, so 5% and
// 100% take the same room and the bar never twitches while the volume is
// being changed.
Text {
    id: t

    // The widest text this item should make room for.
    property string reserve: ""

    font.features: { "tnum": 1 }

    TextMetrics {
        id: metrics
        font: t.font
        text: t.reserve
    }

    readonly property real stableWidth: Math.ceil(Math.max(metrics.advanceWidth, t.implicitWidth))
    Layout.preferredWidth: t.stableWidth
    width: t.stableWidth
}
