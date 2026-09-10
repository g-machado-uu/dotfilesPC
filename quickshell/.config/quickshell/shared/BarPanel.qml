import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.CustomTheme

// A panel that hangs off the status bar.
//
// It is an xdg popup anchored to a bar module, so it tracks that module by
// itself: when the bar expands, contracts or re-lays out, the panel follows the
// icon it belongs to without anyone having to compute coordinates. It drops
// into place as a thick fluid (see FluidReveal).
//
// It is drawn with the bar's own silhouette (BarShape) — same translucent fill,
// no border, and the same concave flares where it meets the bar — so it reads
// as the bar continuing downwards rather than as a card sitting under it.
//
// The open/mapped state lives on this Item rather than inside the PopupWindow,
// so `visible` never depends on the popup's own contents. Content is passed as
// a Component for the same reason: this Item's body already holds the popup and
// the timer, so it cannot also be the content holder.
Item {
    id: panel

    // The bar item the panel hangs from.
    property Item anchorItem: null
    // Driven by the bar. Never written from in here: a click outside or Escape
    // raises dismissed() instead, so the binding that owns `open` survives.
    property bool open: false
    signal dismissed()

    // Which corner of the anchor the panel hangs from, and which way it grows.
    // The default centres it under the anchor. Pass Edges.Bottom | Edges.Right
    // and Edges.Bottom | Edges.Left to pin the panel's right edge to the
    // anchor's right edge and have it grow leftwards instead.
    property int anchorEdges: Edges.Bottom
    property int anchorGravity: Edges.Bottom

    // Size of the panel body, i.e. without the flares that reach past it.
    property real panelWidth: 340
    property real panelHeight: 340
    // Distance between the bottom of the bar and the top of the panel. Zero by
    // default: the flares are what join the two, and a gap would break them.
    property real gap: 0

    // Geometry of the silhouette, normally handed down from the bar's settings
    // so the two always match.
    property real flare: 18
    // Drop the flare on the side where the panel is flush with the bar's edge:
    // the bar squares off that bottom corner at the same time, so the two run
    // on as a single straight edge instead of pinching into each other.
    property real flareLeft: flare
    property real flareRight: flare
    property real cornerRadius: 18
    property real backgroundOpacity: 0.9

    property Component panelContent: null

    // Room below the body for the drop's overshoot, which briefly stretches the
    // panel past its final height. Proportional, because the overshoot is a
    // fraction of the height: a fixed margin would clip a tall panel like the
    // sidebar. There is no horizontal slack and none is needed — FluidReveal's
    // width never overshoots past 1.
    readonly property real padY: Math.max(48, panelHeight * 0.13)

    // The surface has to outlive `open` by the length of the close animation.
    readonly property bool mapped: open || closeDelay.running
    Timer {
        id: closeDelay
        // Longer than FluidReveal's close phase at the default duration.
        interval: 260
    }
    onOpenChanged: {
        if (!panel.open)
            closeDelay.restart()
    }

    // Hand the keyboard to the content, so a panel that navigates with the
    // arrow keys works without the mouse. Focus has to land on the content
    // itself and not merely on the FocusScope around it, or its Keys handlers
    // never see anything; Escape is unhandled there and falls back to the
    // scope. Deferred because the Loader has only just instantiated.
    function focusContent(): void {
        if (contentLoader.item)
            contentLoader.item.forceActiveFocus()
        else
            keyScope.forceActiveFocus()
    }

    // Purely a state holder in the bar's tree; it draws nothing itself.
    implicitWidth: 0
    implicitHeight: 0

    PopupWindow {
        id: popup

        anchor.item: panel.anchorItem
        anchor.edges: panel.anchorEdges
        anchor.gravity: panel.anchorGravity
        anchor.margins.top: panel.gap
        // The anchor rect is deliberately left at its default, which is the
        // whole anchor item: writing anchor.rect.x collapses it to a zero-sized
        // point at the item's top-left, and the panel then hangs off the icon's
        // top corner instead of dropping from under it.

        visible: panel.mapped
        color: "transparent"

        // Wide enough for whichever flares this panel has, tall enough for the
        // overshoot.
        implicitWidth: panel.panelWidth + panel.flareLeft + panel.flareRight
        implicitHeight: panel.panelHeight + panel.padY

        // Click anywhere outside to dismiss, the same primitive the bar uses.
        HyprlandFocusGrab {
            windows: [popup]
            active: panel.open
            onCleared: panel.dismissed()
        }

        onVisibleChanged: {
            if (popup.visible)
                Qt.callLater(panel.focusContent)
        }

        // Takes the keyboard while open so Escape closes the panel. The content
        // sits inside it, so a panel that wants the arrow keys only has to set
        // `focus: true` on itself; Escape still falls through to here.
        FocusScope {
            id: keyScope
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: panel.dismissed()

            FluidReveal {
                anchors.fill: parent
                open: panel.open
                originX: body.x + body.width / 2
                originY: body.y

                Item {
                    id: body
                    width: panel.panelWidth
                    height: panel.panelHeight
                    // Positioned by the left flare rather than centred: the two
                    // flares can differ.
                    x: panel.flareLeft
                    y: 0

                    // The bar's own silhouette and translucency. The opacity
                    // belongs here and not on the content above it, exactly as
                    // in the bar.
                    BarShape {
                        x: -wingLeft
                        y: 0
                        bodyWidth: body.width
                        bodyHeight: body.height
                        flareLeft: panel.flareLeft
                        flareRight: panel.flareRight
                        cornerRadius: panel.cornerRadius
                        fillColor: Theme.background
                        opacity: panel.backgroundOpacity
                    }

                    Loader {
                        id: contentLoader
                        anchors.fill: parent
                        sourceComponent: panel.panelContent
                    }
                }
            }
        }
    }
}
