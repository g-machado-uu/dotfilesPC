import QtQuick
import QtQuick.Shapes

// The silhouette the status bar and everything hanging off it share.
//
// Drawn as one path rather than a rectangle so the two ends can flare
// *outwards* as they reach the surface they grow from. Each end is a concave
// quarter-arc that meets y=0 with a horizontal tangent, so the shape does not
// hang off that surface — it grows out of it, the way a drop forming on a
// ceiling curves back into it. The tip of each flare therefore points along
// the edge, and the two bottom corners are convex to close the drop off.
//
// One filled path, not overlapping shapes: these surfaces are translucent, and
// stacked translucent pieces would show their seams. For the same reason the
// opacity belongs on this item and never on the content drawn over it.
Shape {
    id: shape

    // The body, i.e. the shape without the flares that reach past it.
    property real bodyWidth: 0
    property real bodyHeight: 0
    // How far each end reaches sideways along the top edge.
    property real flare: 18
    // The convex rounding of the two bottom corners.
    property real cornerRadius: 18

    // Per-corner overrides. Setting a flare to 0 gives that side a straight
    // vertical edge, and setting a bottom radius to 0 squares that corner off.
    // Together they let a panel and the bar it hangs from merge into a single
    // silhouette down one side: the bar squares off its bottom corner, the
    // panel drops its flare, and the two edges run on as one line.
    property real flareLeft: flare
    property real flareRight: flare
    property real radiusBottomLeft: cornerRadius
    property real radiusBottomRight: cornerRadius

    property color fillColor: "black"
    // -1 draws no outline at all, which is the norm: these surfaces are plain
    // translucent slabs with no drawn edge.
    property real strokeWidth: -1
    property color strokeColor: "transparent"

    // Clamped so a flare and the bottom corner below it can never meet and fold
    // over each other on a short body.
    readonly property real cornerLeft: Math.min(radiusBottomLeft, bodyHeight)
    readonly property real cornerRight: Math.min(radiusBottomRight, bodyHeight)
    readonly property real wingLeft: Math.min(flareLeft, bodyHeight - cornerLeft)
    readonly property real wingRight: Math.min(flareRight, bodyHeight - cornerRight)

    // The flares extend past the body, so place this at x: -wingLeft relative
    // to the body.
    width: bodyWidth + wingLeft + wingRight
    height: bodyHeight
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: shape.fillColor
        strokeWidth: shape.strokeWidth
        strokeColor: shape.strokeColor

        startX: 0
        startY: 0

        // Left flare: out of the edge and down into the body. Degenerate (a
        // no-op) when wingLeft is 0, which is how a side gets a straight edge.
        PathArc {
            x: shape.wingLeft; y: shape.wingLeft
            radiusX: shape.wingLeft; radiusY: shape.wingLeft
            direction: PathArc.Clockwise
        }
        // Left side, down to where the bottom corner starts.
        PathLine { x: shape.wingLeft; y: shape.height - shape.cornerLeft }
        // Bottom-left corner.
        PathArc {
            x: shape.wingLeft + shape.cornerLeft; y: shape.height
            radiusX: shape.cornerLeft; radiusY: shape.cornerLeft
            direction: PathArc.Counterclockwise
        }
        // Bottom edge.
        PathLine {
            x: shape.width - shape.wingRight - shape.cornerRight
            y: shape.height
        }
        // Bottom-right corner.
        PathArc {
            x: shape.width - shape.wingRight
            y: shape.height - shape.cornerRight
            radiusX: shape.cornerRight; radiusY: shape.cornerRight
            direction: PathArc.Counterclockwise
        }
        // Right side, back up to the flare.
        PathLine { x: shape.width - shape.wingRight; y: shape.wingRight }
        // Right flare, back out to the edge.
        PathArc {
            x: shape.width; y: 0
            radiusX: shape.wingRight; radiusY: shape.wingRight
            direction: PathArc.Clockwise
        }
        // Close along the top edge.
        PathLine { x: 0; y: 0 }
    }
}
