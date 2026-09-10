import QtQuick

// A wrapper that makes its contents appear as if a thick drop of fluid were
// pushed out of the status bar: the shape first stretches down from `originY`
// in a narrow column, overshoots, then spreads sideways and settles into its
// final size. Closing sucks it back into the same point.
//
// Usage:
//   FluidReveal {
//       anchors.fill: parent
//       open: root.isOpen
//       // ...content...
//   }
//   visible: fluid.active   // keep the surface mapped while it plays
Item {
    id: fluid

    // Drives the animation. Set it, don't animate it.
    property bool open: false

    // The point the drop hangs from, in this item's own coordinates.
    // Defaults to the top centre, i.e. the edge nearest the bar.
    property real originX: width / 2
    property real originY: 0

    // How squashed the shape is at rest (closed).
    property real seedXScale: 0.62
    property real seedYScale: 0.12

    // Overall pace. Everything below is a fraction of this, so a single
    // number tunes the whole feel.
    property int duration: 280

    readonly property bool running: inAnim.running || outAnim.running
    // True whenever the surface still needs to be on screen.
    readonly property bool active: open || running

    property real xScale: seedXScale
    property real yScale: seedYScale
    opacity: 0

    transform: Scale {
        origin.x: fluid.originX
        origin.y: fluid.originY
        xScale: fluid.xScale
        yScale: fluid.yScale
    }

    // onOpenChanged does not fire for an initial value, so snap to the final
    // state if the wrapper is constructed already open.
    Component.onCompleted: {
        if (open) {
            xScale = 1.0
            yScale = 1.0
            opacity = 1.0
        }
    }

    onOpenChanged: {
        if (open) {
            outAnim.stop()
            inAnim.restart()
        } else {
            inAnim.stop()
            outAnim.restart()
        }
    }

    // Opening: the column falls first (OutBack overshoots past full height,
    // like a drop stretching), the width follows a beat later and splashes
    // out to the final shape.
    ParallelAnimation {
        id: inAnim

        NumberAnimation {
            target: fluid; property: "opacity"; to: 1.0
            duration: Math.round(fluid.duration * 0.4)
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: fluid; property: "yScale"; to: 1.0
            duration: fluid.duration
            easing.type: Easing.OutBack
            easing.overshoot: 1.9
        }
        SequentialAnimation {
            PauseAnimation { duration: Math.round(fluid.duration * 0.22) }
            // Spreads out to its final width without overshooting it: the
            // surface is exactly as wide as the shape plus its flares, so any
            // horizontal overshoot would be clipped.
            NumberAnimation {
                target: fluid; property: "xScale"; to: 1.0
                duration: Math.round(fluid.duration * 0.82)
                easing.type: Easing.OutQuint
            }
        }
    }

    // Closing is deliberately shorter — it should feel snapped back, not
    // played in reverse.
    ParallelAnimation {
        id: outAnim

        NumberAnimation {
            target: fluid; property: "yScale"; to: fluid.seedYScale
            duration: Math.round(fluid.duration * 0.6)
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: fluid; property: "xScale"; to: fluid.seedXScale
            duration: Math.round(fluid.duration * 0.6)
            easing.type: Easing.InQuad
        }
        SequentialAnimation {
            PauseAnimation { duration: Math.round(fluid.duration * 0.22) }
            NumberAnimation {
                target: fluid; property: "opacity"; to: 0.0
                duration: Math.round(fluid.duration * 0.38)
                easing.type: Easing.InQuad
            }
        }
    }
}
