import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One product in the POS tile grid — in the two shapes a product card comes in.
 *
 *     PosTile {
 *         name: row.name
 *         priceText: row.price_text      // already formatted in Python
 *         stock: row.stock
 *         stockText: row.stock_text
 *         lowStock: row.low_stock
 *         accent: row.colour
 *         showImage: page.imageCards     // the grid decides, not the row
 *         imageSource: row.image         // "" for a product without a photo
 *         onClicked: page.pick(row)
 *     }
 *
 *   WITHOUT A PHOTO (120px)          WITH ONE (244px)
 *   ┌─────────────────────────┐      ┌─────────────────────────┐
 *   │▌ Coca-Cola 1.5L         │      │▌ ┌───────────────────┐  │
 *   │▌                        │      │▌ │                   │  │
 *   │▌ 120,00 DA     ⟨2 pcs⟩  │      │▌ │      [photo]      │  │
 *   └─────────────────────────┘      │▌ └───────────────────┘  │
 *                                    │▌ Coca-Cola 1.5L         │
 *                                    │▌ 120,00 DA     ⟨2 pcs⟩  │
 *                                    └─────────────────────────┘
 *
 * WHY TWO SHAPES AND NOT TWO COMPONENTS
 *
 * Everything below the photo is identical — the same name, the same price, the
 * same stock pill, the same accent, the same press feedback, the same tooltip.
 * Two files would be two places to fix the next thing that is wrong with a
 * product card, and they would drift: this is the mistake the till's own header
 * describes making with its search results. So the photo is a band this card
 * grows, and `showImage` is the one property that says whether it has it.
 *
 * WHY THE GRID DECIDES AND NOT THE ROW
 *
 * A GridView has ONE cellHeight. If each card chose for itself, a category where
 * three products have photos would lay 244px cards and 120px cards into cells of
 * one size — clipping some and stranding others in a sea of white. So the page
 * asks the controller once (`Till.imageCards`) and every card in the grid answers
 * the same way; a product with no photo of its own gets the placeholder below
 * rather than a different card.
 *
 * WHY THE PLACEHOLDER IS A GLYPH AND NOT THE PRODUCT'S INITIAL
 *
 * The first version put the product's own first letter on its category's colour,
 * on the argument that a repeated grey glyph says "forty things are missing"
 * while a letter differentiates. Rendering it against a real catalogue killed
 * that: shops name products with the brand first — Atlas Milk, Atlas Rice, Atlas
 * Salt — so the wall read A A A A A, which differentiates nothing and competes
 * with the name printed directly underneath it. A quiet "no photo" mark is the
 * honest answer, and the shop photographs its catalogue one product at a time
 * either way.
 *
 * WHY THE STOCK IS ON EVERY TILE
 *
 * It used to appear only at zero and near zero, on the argument that a number on
 * two hundred tiles is noise. That was wrong in the one direction that matters: a
 * cashier deciding whether to promise the customer a second bottle needs the count
 * BEFORE the tap, and a tile that only speaks when the news is bad teaches nothing
 * about the shelf. It is quiet when it is healthy — a neutral pill, not a coloured
 * one — and it colours itself only when the number changes what somebody would do.
 *
 * WHY IT SELLS AT ZERO, AND BELOW
 *
 * pos calls setEnabled(stock > 0). A disabled tile on a touchscreen is
 * indistinguishable from a frozen application — the operator taps, nothing happens,
 * and nothing explains why — and it also kills the tooltip, so the one place pos
 * writes "out of stock" is unreachable on the tile that needs it.
 *
 * More than that, refusing the tap was the WRONG RULE. `finalize_sale` lets stock go
 * negative on purpose (pos/app/data/db.py:1241-1243): a shop sells the case that is
 * still on the pallet, or the count is simply wrong, and the sale is real either
 * way. The tile stays live, full-contrast and tappable at any stock level; what
 * changes is the pill, which turns red and shows the negative it will create. The
 * count is the warning, not the barrier.
 *
 * WHERE `accent` COMES FROM
 *
 * pos lets a product carry a user-chosen colour and is the one place in that
 * codebase permitted to inline a stylesheet for it. It is passed in here rather
 * than derived, so the page is free to fall back to the category's hue when a
 * product has no colour of its own — which is what actually makes a wall of
 * tiles scannable, since almost nobody colours products one at a time.
 *
 * WHY AbstractButton AND NOT Button
 *
 * A tile needs the whole of a button's behaviour — hover, press, keyboard
 * activation, Accessible.name — and none of a button's appearance. Starting from
 * the styled Button would have meant replacing its background and contentItem,
 * which is how a control quietly opts out of the geometry the vendoring scaler
 * multiplied. AbstractButton ships with `background` and `contentItem` both
 * null, so everything below is additive: there is nothing here to override.
 */
QC.AbstractButton {
    id: tile

    // =====================================================================
    // API
    // =====================================================================
    property string name: ""
    /* Money arrives already formatted. Every amount in this app is formatted by
       pos's own fmt_money, which knows the currency, the decimal count and the
       digit shapes for the active language; a second implementation in JS would
       be a second set of rules for the same money. */
    property string priceText: ""
    property string barcode: ""

    /* The product's photo, as a URL. "" is a product without one, and so is a
       photo whose file has gone missing — the bridge answers "" for both, and
       there is nothing a card could usefully do differently about the second. */
    property string imageSource: ""

    /* Does this card have a photo band at all? The GRID's answer, not the row's
       — see the header. */
    property bool showImage: false

    /* Is there a picture to draw in it? */
    readonly property bool hasImage: showImage && imageSource !== ""

    /* Raw, because it decides the pill's tone. */
    property real stock: 0
    property string stockText: ""
    property bool lowStock: false

    /* "transparent" means "no colour set" — a `color` property cannot be null,
       and a zero alpha is the one value that can never be a real choice. */
    property color accent: "transparent"
    readonly property bool tinted: accent.a > 0

    /* Room to keep clear at the trailing end of the NAME, for something the host
       draws over the card's top corner.
       The arrange screen puts a favourite star there. It fitted while that grid was
       pinned to three columns and the tiles were 440px wide; the moment the grid
       started flowing from `tileMin` like the till's, the star landed on top of the
       product name. Nothing else on the face moves — the price row is at the bottom
       and the corner is at the top. */
    property int nameTrailingRoom: 0

    /* There is stock on the shelf. NOT "can be sold" — see the header. */
    readonly property bool inStock: stock > 0
    readonly property bool oversold: stock < 0
    readonly property bool striped: tinted

    /*
     * The stock pill's tone, and the whole of the tile's warning vocabulary.
     *
     *   below zero   danger, and the pill shows the negative it already is
     *   at zero      danger — the next sale makes it negative
     *   low          warning
     *   healthy      "" — a neutral pill, information rather than an alarm
     */
    readonly property string stockTone: (oversold || stock === 0) ? "danger"
                                      : lowStock ? "warning" : ""

    // =====================================================================
    // BEHAVIOUR
    // =====================================================================
    hoverEnabled: true
    implicitWidth: showImage ? Tokens.size.tileMediaMin : Tokens.size.tileMin
    implicitHeight: showImage ? Tokens.size.tileMedia : Tokens.size.tile

    /* Padding is set here, once, rather than on each label — Control hands
       contentItem exactly the area between its paddings, so this is the single
       place the face's inset is decided.
       It is also the one kind of geometry LayoutMirroring does NOT flip: anchors
       and positioners mirror, padding does not. So the extra room the stripe
       needs is placed by asking `mirrored`, which is the same property the style
       itself uses and which accounts for the control's locale as well as an
       ancestor's LayoutMirroring. */
    readonly property int stripeRoom: striped ? 4 + Tokens.spacing.xs : 0
    topPadding: Tokens.spacing.sm
    bottomPadding: Tokens.spacing.sm
    leftPadding: Tokens.spacing.sm + (mirrored ? 0 : stripeRoom)
    rightPadding: Tokens.spacing.sm + (mirrored ? stripeRoom : 0)

    Accessible.role: Accessible.Button
    Accessible.name: name
    Accessible.description: inStock
        ? priceText
        : Strings.t("pos.tile.out_of_stock", "Out of stock")

    /* Tooltip carries what will not fit on the face: the untruncated name, the
       barcode, and the stock in words. Same three facts pos puts there. */
    QC.ToolTip.text: {
        var lines = [name]
        if (barcode !== "")
            lines.push(barcode)
        lines.push(inStock
                   ? stockText
                   : Strings.t("pos.tile.out_of_stock", "Out of stock"))
        return lines.join("\n")
    }
    QC.ToolTip.visible: hovered && name !== ""
    QC.ToolTip.delay: 700

    /* Press feedback. A transform, so it costs the compositor nothing, and on a
       touchscreen it is the only confirmation that the tap landed — pos forbids
       animation outright, but that was a Qt Widgets repaint-cost rule and it does
       not apply to a scene graph. */
    scale: down ? 0.97 : 1.0
    Behavior on scale {
        NumberAnimation { duration: Fluent.anim.speed; easing.type: Easing.OutQuint }
    }

    // =====================================================================
    // SURFACE
    // =====================================================================
    background: Rectangle {
        radius: Tokens.radius.md

        /* No dead-grey state. A tile at zero stock is still a live, tappable
           product — the stock pill is what says so, and greying the surface was
           the visual half of a refusal this tile no longer makes. */
        color: {
            if (tile.tinted) {
                /* The product's own colour at a tenth strength — enough to sort
                   a grid by eye, faint enough that text on top still clears
                   contrast. pos uses tint(color, 0.85) for the same purpose. */
                return Qt.tint(Fluent.cardBackground,
                               Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b,
                                       tile.down ? 0.22 : tile.hovered ? 0.16 : 0.10))
            }
            return tile.down ? Fluent.subtleTertiary
                 : tile.hovered ? Fluent.subtleSecondary
                                : Fluent.cardBackground
        }

        border.width: 1
        /* Oversold is worth a border, not just a pill: at a glance across a wall
           of tiles the outline is what carries, and a product already below zero
           is the one thing on this screen somebody may want to stop and check. */
        border.color: tile.oversold
            ? Qt.rgba(Tokens.danger.r, Tokens.danger.g, Tokens.danger.b, 0.55)
            : tile.tinted
              ? Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.45)
              : Fluent.dividerBorder

        /* Leading-edge stripe in the product's colour. Anchors flip under
           LayoutMirroring, so this is the leading edge in Arabic too.

           Inset top and bottom by the card's own radius: the stripe is a
           square-cornered child of a rounded parent, and a rounded Rectangle
           clips to its bounding box rather than its arcs, so a full-height
           stripe would show a small nub outside each corner. Starting where the
           straight edge starts avoids the problem geometrically. */
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: Tokens.radius.md
            anchors.bottomMargin: Tokens.radius.md
            width: 4
            radius: 2
            visible: tile.striped
            color: tile.accent
        }

        // Keyboard focus. Drawn, not borrowed: AbstractButton has no style to
        // supply a focus ring.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 2
            border.color: Fluent.accent
            visible: tile.visualFocus
        }
    }

    // =====================================================================
    // FACE
    // =====================================================================
    /* Anchored rather than stacked in a Column. The two rows have fixed
       relationships to the tile's edges — name to the top, price to the bottom —
       and the slack belongs in the middle, where a name that runs to one line
       instead of two should leave it. A Column would have to sum to exactly the
       tile height to look right at every name length. */
    contentItem: Item {

        /*
         * The photo band.
         *
         * Anchored to the top and given a height of zero when there is no band,
         * so the name below it can anchor to `media.bottom` unconditionally —
         * with no band, that IS the top of the face. One anchor, two shapes.
         *
         * SQUARE CORNERS, ON PURPOSE. A rounded Rectangle in Qt Quick clips its
         * children to its bounding box and not to its arcs, so an Image inside a
         * radius-6 frame paints over all four corners and the rounding is a lie
         * that only shows at the edges. There is no cheap rounded clip to reach
         * for — the alternative is a render layer and an OpacityMask per visible
         * card, on a screen that scrolls forty of them — so the band is a framed
         * photograph rather than a rounded one, and the frame is what makes that
         * read as deliberate. The card around it keeps its radius: nothing
         * overpaints ITS corners.
         */
        Item {
            id: media
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: tile.showImage ? Tokens.size.tileImage : 0
            visible: tile.showImage

            Rectangle {
                id: frame
                anchors.fill: parent
                clip: true

                /* The ground under the picture, and the whole of the placeholder:
                   the category's colour at a low strength, or a neutral step off
                   the card when a product has no category to borrow from. Also
                   what is on screen for the frame or two an asynchronous decode
                   takes, which is why it is a colour and not white. */
                color: tile.tinted
                       ? Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.14)
                       : Fluent.subtleTertiary
                border.width: 1
                border.color: tile.tinted
                              ? Qt.rgba(tile.accent.r, tile.accent.g,
                                        tile.accent.b, 0.35)
                              : Fluent.dividerBorder

                Icon {
                    anchors.centerIn: parent
                    visible: !tile.hasImage
                    icon: "ic_fluent_image_off_20_regular"
                    size: Tokens.icon.lg
                    color: tile.tinted ? tile.accent : Fluent.textTertiary
                    opacity: 0.45
                }

                Image {
                    anchors.fill: parent
                    visible: tile.hasImage
                    source: tile.hasImage ? tile.imageSource : ""
                    /* Fill the band and crop the overflow: a letterboxed photo
                       leaves two grey bars on every card and turns a wall of
                       products into a wall of frames. */
                    fillMode: Image.PreserveAspectCrop
                    /* Never on the GUI thread: a till that stutters while it
                       reads forty files off a disk is a till that misses taps. */
                    asynchronous: true
                    /* Decoded at twice the card's width and no more. Stored photos
                       are capped at 640px, and a full-size decode per visible card
                       is tens of megabytes for pixels no screen shows. Only one
                       dimension is set — the other follows the aspect ratio, which
                       is what PreserveAspectCrop needs to crop rather than
                       stretch. */
                    sourceSize.width: 2 * Tokens.size.tileMediaMin
                    mipmap: true
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            /* Mirrors with the anchor: under LayoutMirroring `right` becomes `left`
               and the margin travels with it, so the cleared corner is the trailing
               one in Arabic too. */
            anchors.rightMargin: tile.nameTrailingRoom
            anchors.top: media.bottom
            anchors.topMargin: tile.showImage ? Tokens.spacing.sm : 0
            height: Tokens.size.tileName

            text: tile.name
            font.pixelSize: Tokens.font.tileName
            font.weight: Font.DemiBold
            color: Fluent.textPrimary
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            /* Logical alignment: mirrors to AlignRight in Arabic. Pinned rather
               than left to default because a Text with no explicit alignment
               follows its OWN content's direction, which would put a
               French-named product on the wrong edge of an Arabic screen. */
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignTop
        }

        /* A Layout, so the pill claims its width and the price takes the rest,
           and so the pair swaps sides in Arabic without either of them being
           told to. */
        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: Tokens.spacing.xs

            Text {
                Layout.fillWidth: true
                text: tile.priceText
                font.pixelSize: Tokens.font.tilePrice
                font.weight: Font.DemiBold
                /* Tabular figures: a wall of prices in one column is only
                   comparable if the digits are one width. */
                font.features: Tokens.figures
                color: Fluent.textPrimary
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
            }

            /* The stock, on every tile. Neutral while it is healthy, coloured when
               the number changes what somebody would do — see the header. */
            Rectangle {
                id: stockPill
                Layout.alignment: Qt.AlignVCenter

                readonly property bool alarmed: tile.stockTone !== ""

                implicitWidth: stockLabel.implicitWidth + Tokens.spacing.sm
                implicitHeight: stockLabel.implicitHeight + Tokens.spacing.xs
                radius: Tokens.radius.pill
                color: alarmed ? Tokens.toneFill(tile.stockTone)
                               : Fluent.subtleTertiary

                Text {
                    id: stockLabel
                    anchors.centerIn: parent
                    /* The number itself, always — including a negative one. This
                       used to print a hardcoded "0" whenever stock was not
                       positive, so a product already at −3 reported zero and the
                       oversell was invisible on the one surface that could have
                       shown it. */
                    text: "\u200e" + (tile.stockText !== ""
                                      ? tile.stockText : String(tile.stock))
                    font.pixelSize: Tokens.font.caption
                    font.weight: Font.DemiBold
                    font.features: Tokens.figures
                    color: stockPill.alarmed ? Tokens.toneInk(tile.stockTone)
                                             : Fluent.textSecondary
                }
            }
        }
    }
}
