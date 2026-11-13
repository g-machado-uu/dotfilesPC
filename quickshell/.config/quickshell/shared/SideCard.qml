import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import qs.CustomTheme

// A card that grows sideways out of the edge of a panel, and is sucked back
// into it when it closes. The notification list, which grows out of the
// control centre's right edge, is the one that uses it.
//
// Unlike BarPanel, this is *not* drawn as the bar continuing downwards. It
// grows out of the *panel* beside it the way a branch grows off a trunk: a
// short stem joins the two at the top left, and everything below that stands
// clear of the panel by a few pixels. So the card is square only at the corner
// the stem meets, and rounded on the other three. It starts as a small nub
// level with the row it came from (the control centre's Open button) and opens
// out rightwards and downwards into the full card.
//
// The stem meets the panel the way the bar meets the top of the screen: with a
// concave quarter-arc above and below it, tangent to the panel's edge, so the
// branch thickens into the trunk instead of being butted against it. It is the
// same idea as BarShape's flares, turned on its side — that one grows out of a
// horizontal surface, this one out of a vertical edge — which is why the stem
// is a Shape and not a rectangle.
//
// Its underside is flared at *both* ends, so the joint has no square corner
// anywhere: one sweep down into the panel it came from, another down into the
// card. The two are the same quarter-arc mirrored, each reaching half the gap
// across, so they meet in the exact middle of the gap with a horizontal
// tangent on both sides — one continuous, symmetric valley. The card-side
// sweep lands on the rule under that card's header (attachCardY), so the joint
// ends on a line that is already there; the stem's height follows from that
// rather than being set on its own.
//
// How it animates, and why it animates this way:
//
//   The whole motion is one property, `reveal` (0 closed, 1 open), and the only
//   thing it drives is the width of a rounded rectangle. The window underneath
//   never changes size and never moves, and the content inside is laid out once
//   at the card's full width and simply clipped — so no frame of the animation
//   costs a window resize, a popup reposition or a re-layout of the list. That
//   matters: the first version of this panel animated the *anchor* of a mapped
//   popup, which asks the compositor to reposition the surface on every frame,
//   and it was visibly laggy.
//
//   Because the background is the rectangle that grows (rather than a full-width
//   one revealed behind a moving edge) the card reads as growing out of the
//   panel: at a small width Qt clamps the corner radius to half the width, so it
//   starts as a lozenge and opens out into the card.
//
//   The content is not drawn at all while the card is growing — it fades in once
//   the card is open, and fades out before it shrinks. That is not only how it
//   looks: a clip rectangle that changes every frame with text inside it makes
//   Qt rebuild its render batches on every one of those frames, which measured
//   at ~4.7 ms of CPU per frame. With nothing in the card but the rectangle, the
//   growth is one quad a frame.
Item {
    id: card

    // The item the card hangs off. With the default edges below, the card's
    // left edge lands on this item's right edge.
    property Item anchorItem: null
    // Driven by the owner. Never written from in here: a click outside or
    // Escape raises dismissed() instead, so the binding that owns `open`
    // survives.
    property bool open: false
    signal dismissed()

    // Whether the card takes the keyboard and closes on a click outside. Off
    // when the panel it spawned from holds the grab for both (see grabAlso on
    // BarPanel) — two grabs would fight over the pointer.
    property bool grabFocus: true
    // Further windows this card's own grab should treat as its own.
    property var grabAlso: []
    // This card's surface, for the other panel's grabAlso.
    readonly property var grabWindow: popup
    // True while the pointer is over the card.
    readonly property bool hovered: bodyHover.hovered

    // Size of the card itself, once it is fully out.
    property real cardWidth: 380
    property real cardHeight: 520
    // How far down the card's top edge sits, measured from the bottom of the
    // anchor. The top never moves: the card grows downwards from it, so this is
    // the height of the row it appears to come out of.
    property real topInset: 8
    // The height of the nub the growth starts from, so the card begins level
    // with that row rather than as a sliver.
    property real minHeight: 34
    property real cornerRadius: 18
    // The corner the stem joins, kept square so the two meet without a seam.
    property real attachRadius: 0
    // How far the card stands clear of the panel it grows from, and how tall
    // the stem that bridges that gap is. The stem is the height of the opening
    // nub by default, so the card starts as a bud on the panel's edge and the
    // joint stays that size as the card opens out below it.
    property real attachGap: 12
    // The stem at its narrowest, in the middle of the gap. Derived, so that a
    // sweep of attachFlare puts the card-side edge of the joint exactly on
    // attachCardY.
    property real attachHeight: Math.max(0, card.attachCardY - card.attachFlare)
    // The radius of every sweep of the joint, panel side and card side alike.
    // Half the gap, so the two halves of the underside meet in the middle of
    // it and the joint is symmetric.
    property real attachFlare: card.attachGap / 2
    // Where the card-side sweep lands on the card's edge, measured from the
    // card's top. The card tells the bar where its header rule is.
    property real attachCardY: 52
    property real backgroundOpacity: 0.9
    property int revealDuration: 320

    // Pinned by its left edge to the anchor's right edge, growing rightwards.
    property int anchorEdges: Edges.Bottom | Edges.Right
    property int anchorGravity: Edges.Bottom | Edges.Right
    // Distance between the bottom of the anchor and the top of the popup.
    property real gap: 0

    property Component cardContent: null
    readonly property Item content: contentLoader.item

    // The animation is two values, not one, because the card does not simply
    // scale up: it reaches out first and fills out second. The width runs ahead
    // on a decelerating curve, so the card is already most of the way across
    // while it is still only a nub tall, and the height follows on an
    // ease-in-out that does most of its work in the second half.
    property real reveal: card.open ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: card.revealDuration
            easing.type: Easing.OutCubic
        }
    }

    property real heightReveal: card.open ? 1 : 0
    Behavior on heightReveal {
        NumberAnimation {
            duration: card.revealDuration
            easing.type: Easing.InOutCubic
        }
    }

    // The surface has to outlive `open` by the length of the close animation,
    // which the two reveals already describe.
    readonly property bool mapped: card.open
        || card.reveal > 0.001 || card.heightReveal > 0.001

    // The content is shown only while the card is fully out: the growth and the
    // shrink have nothing in them but the rounded rectangle.
    readonly property bool contentShown:
        card.open && card.reveal >= 1 && card.heightReveal >= 1
    property real contentFade: card.contentShown ? 1 : 0
    Behavior on contentFade {
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
    }

    // Purely a state holder in the bar's tree; it draws nothing itself.
    implicitWidth: 0
    implicitHeight: 0

    // Hand the keyboard to the content, the same way BarPanel does.
    function focusContent(): void {
        if (contentLoader.item)
            contentLoader.item.forceActiveFocus()
        else
            keyScope.forceActiveFocus()
    }

    PopupWindow {
        id: popup

        anchor.item: card.anchorItem
        anchor.edges: card.anchorEdges
        anchor.gravity: card.anchorGravity
        // Spelled out as bindings so the popup follows the anchor as it is
        // resized — see the note in BarPanel. Nothing here animates them.
        anchor.rect.width: card.anchorItem ? card.anchorItem.width : 0
        anchor.rect.height: (card.anchorItem ? card.anchorItem.height : 0)
            + card.gap

        visible: card.mapped
        color: "transparent"

        // Constant: the card grows inside the window, not with it.
        implicitWidth: card.attachGap + card.cardWidth
        implicitHeight: card.cardHeight + card.topInset

        HyprlandFocusGrab {
            windows: [popup].concat(card.grabAlso)
            active: card.open && card.grabFocus
            onCleared: card.dismissed()
        }

        onVisibleChanged: {
            if (popup.visible)
                Qt.callLater(card.focusContent)
        }

        FocusScope {
            id: keyScope
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: card.dismissed()

            // The stem. It bridges the gap between the panel and the card at
            // the top left and nowhere else, so the card reads as growing off
            // the panel rather than as a slab pushed up against it.
            //
            // Widest where it meets the panel and narrowing to the stem's own
            // height by the time it reaches the card, with both of those
            // transitions a concave quarter-arc tangent to the panel's edge.
            //
            // Drawn exactly adjacent to the card, never overlapping it: these
            // surfaces are translucent, and two of them over one another would
            // show as a darker band down the joint (the same reason BarShape is
            // one path rather than several pieces).
            Shape {
                id: stem
                // Reach of the panel-side flare, across and along the edge.
                readonly property real f: card.attachFlare
                // Reach of the card-side sweep: whatever of the gap the
                // panel-side flare leaves, and down to the card's header rule.
                // Mirror of the panel-side flare, so both are circular and of
                // the same radius.
                readonly property real nx: stem.f
                readonly property real ny: stem.f
                // The card's top edge, in this shape's coordinates.
                readonly property real cardTop: stem.f

                x: 0
                y: card.topInset - stem.cardTop
                width: card.attachGap
                height: stem.cardTop
                    + Math.max(card.attachCardY, card.attachHeight + stem.f)
                visible: card.reveal > 0
                opacity: card.backgroundOpacity
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: Theme.background
                    strokeWidth: -1

                    // Top of the upper flare, on the panel's edge.
                    startX: 0
                    startY: 0

                    // Out of the edge and across to the card: vertical tangent
                    // where it leaves the panel, horizontal where it arrives.
                    PathArc {
                        x: stem.f; y: stem.cardTop
                        radiusX: stem.f; radiusY: stem.f
                        direction: PathArc.Counterclockwise
                    }
                    // The stem's top edge, running on into the card's own top
                    // edge: both are at the card's top, so there is no corner
                    // between them to soften.
                    PathLine { x: card.attachGap; y: stem.cardTop }
                    // Down the side that butts against the card, as far as the
                    // rule under its header.
                    PathLine {
                        x: card.attachGap
                        y: stem.cardTop + card.attachCardY
                    }
                    // The card-side sweep: away from the card's edge (vertical
                    // tangent) and up onto the underside of the stem
                    // (horizontal tangent).
                    PathArc {
                        x: card.attachGap - stem.nx
                        y: stem.cardTop + card.attachHeight
                        radiusX: stem.nx; radiusY: stem.ny
                        direction: PathArc.Counterclockwise
                    }
                    // The panel-side sweep, mirroring the arc at the top. It
                    // starts with a horizontal tangent too, so the two meet as
                    // one continuous valley rather than at a point.
                    PathArc {
                        x: 0
                        y: stem.cardTop + card.attachHeight + stem.f
                        radiusX: stem.f; radiusY: stem.f
                        direction: PathArc.Counterclockwise
                    }
                    // Close up the panel's edge.
                    PathLine { x: 0; y: 0 }
                }
            }

            // The growing card. Its width and height are the animation;
            // everything inside is laid out at the card's full size and clipped
            // by it. The top edge stays put, so it opens out downwards.
            Item {
                id: body
                x: card.attachGap
                y: card.topInset
                width: card.cardWidth * card.reveal
                height: card.minHeight
                    + (card.cardHeight - card.minHeight) * card.heightReveal
                clip: true

                // Passive, so the content's own MouseAreas still hover.
                HoverHandler {
                    id: bodyHover
                }

                // The card itself. It fills the growing item, so it is always a
                // properly rounded rectangle rather than a full-width one with
                // its right edge cut off. The translucency belongs here and not
                // on the content above it, exactly as in the bar.
                Rectangle {
                    anchors.fill: parent
                    // Square only where the stem lands; the other three corners
                    // are free of the panel and rounded like any other card.
                    topLeftRadius: card.attachRadius
                    bottomLeftRadius: card.cornerRadius
                    topRightRadius: card.cornerRadius
                    bottomRightRadius: card.cornerRadius
                    color: Theme.background
                    opacity: card.backgroundOpacity
                }

                Loader {
                    id: contentLoader
                    x: 0
                    y: 0
                    // Always the full card: laying the list out once and
                    // clipping it is what keeps the animation free of
                    // re-layout.
                    width: card.cardWidth
                    height: card.cardHeight
                    opacity: card.contentFade
                    // Culled outright while invisible, so a growing or
                    // shrinking card costs nothing to draw.
                    visible: card.contentFade > 0
                    // Built when the card opens and destroyed once it has
                    // closed, so a closed card costs no memory. Content starts
                    // fresh on every open (and is created with isOpen already
                    // true, so on-open work belongs in Component.onCompleted
                    // too).
                    active: card.mapped
                    sourceComponent: card.cardContent
                }
            }
        }
    }
}
