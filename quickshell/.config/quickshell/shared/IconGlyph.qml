import QtQuick
import QtQuick.Effects

// A stroke SVG recoloured to an arbitrary colour — the same treatment the bar's
// buttons give their icons, pulled out so panels can reuse it.
Item {
    id: glyph

    property string source: ""
    property real size: 18
    property color color: "white"

    implicitWidth: size
    implicitHeight: size

    Image {
        anchors.fill: parent
        source: glyph.source
        sourceSize.width: glyph.size
        sourceSize.height: glyph.size
        fillMode: Image.PreserveAspectFit
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: glyph.color
            Behavior on colorizationColor {
                ColorAnimation { duration: 180; easing.type: Easing.OutQuint }
            }
        }
    }
}
