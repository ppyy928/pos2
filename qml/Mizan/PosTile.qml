import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One product in the POS tile grid — compact, image-left, text-right.
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
 *   WITHOUT A PHOTO (the text tile, 102px)   WITH ONE (the image card, 122px)
 *   ┌─────────────────────┐                 ┌────────┬──────────────────────┐
 *   │ Coca-Cola 1.5L      │                 │        │ Coca-Cola 1.5L       │
 *   │ two-litre bottle,   │                 │ square │ two-litre bottle,    │
 *   │ chilled             │                 │  84px  │ chilled              │
 *   │ 120,00 DA     24 pcs│                 │        │ 120,00 DA     24 pcs │
 *   └─────────────────────┘                 └────────┴──────────────────────┘
 *
 * Both faces give the name two lines — a name forced into one truncated line
 * is a name an operator cannot match to the goods in front of them, and a
 * name given three is a money block pushed off the card.
 *
 * THE IMAGE CARD IS HORIZONTAL
 *
 * The photo used to be a wide band ABOVE the words, which spent 40% of every
 * card's height on a picture most products do not have and pushed the name
 * under it. Here the photo is a true square on the leading edge — aspect-fill,
 * never stretched, 84px, the size a photo needs to be recognised rather than
 * admired — and every word sits beside it. The no-photo card keeps the
 * text-first face it has always had: a product without a photo is the normal
 * case, not a degraded one, and the placeholder square exists only where a
 * photo COULD be, so the wall stays one shape.
 *
 * THE PLACEHOLDER IS A QUIET BOX
 *
 * A product with no photo of its own (or whose file has gone missing — the
 * bridge answers "" for both) gets a neutral square with a package glyph in
 * it: no broken-image symbol, no large pastel rectangle, no random colour.
 * The square keeps the photo's exact dimensions, so a mixed wall stays a grid.
 *
 * THE COLOUR IS A STRIPE, NOT A WASH
 *
 * pos lets a product carry a user-chosen colour, and it is real data — a
 * merchant sorts their wall by it. It is drawn as a 3px stripe on the leading
 * edge and as the square's frame at low strength when there is a photo, and
 * nowhere else: no pastel wash, no tinted border. A wall of forty
 * differently-pastelled cards is noise; a wall of quiet cards with a colour
 * key on the edge is a sort.
 *
 * WHY THE STOCK IS ON EVERY TILE
 *
 * A cashier deciding whether to promise the customer a second bottle needs
 * the count BEFORE the tap. It is quiet text while it is healthy and colours
 * itself only when the number changes what somebody would do — a pill for
 * the alarms, plain secondary text for the everyday number. On a narrow
 * image card the stock wraps under the price rather than eliding, because
 * "Sto…" is not information.
 *
 * WHY IT SELLS AT ZERO, AND BELOW
 *
 * pos calls setEnabled(stock > 0). A disabled tile on a touchscreen is
 * indistinguishable from a frozen application — the operator taps, nothing
 * happens, and nothing explains why — and it also kills the tooltip, so the
 * one place pos writes "out of stock" is unreachable on the tile that needs
 * it. More than that, refusing the tap was the WRONG RULE:
 * `finalize_sale` lets stock go negative on purpose (pos/app/data/db.py):
 * a shop sells the case that is still on the pallet, or the count is simply
 * wrong, and the sale is real either way. The tile stays live, full-contrast
 * and tappable at any stock level; what changes is the stock text, which
 * turns red and shows the negative it will create. The count is the warning,
 * not the barrier.
 *
 * WHY AbstractButton AND NOT Button
 *
 * A tile needs the whole of a button's behaviour — hover, press, keyboard
 * activation, Accessible.name — and none of a button's appearance. Starting
 * from the styled Button would have meant replacing its background and
 * contentItem, which is how a control quietly opts out of the geometry the
 * vendoring scaler multiplied. AbstractButton ships with `background` and
 * `contentItem` both null, so everything below is additive.
 */
QC.AbstractButton {
    id: tile

    // =====================================================================
    // API
    // =====================================================================
    property string name: ""
    /* Money arrives already formatted. Every amount in this app is formatted
       by pos's own fmt_money, which knows the currency, the decimal count and
       the digit shapes for the active language; a second implementation in JS
       would be a second set of rules for the same money. */
    property string priceText: ""

    property string barcode: ""

    /* The product's photo, as a URL. "" is a product without one, and so is a
       photo whose file has gone missing — the bridge answers "" for both, and
       there is nothing a card could usefully do differently about the second. */
    property string imageSource: ""

    /* Does this card have a photo band at all? The GRID's answer, not the
       row's — a GridView has one cellHeight, so per-row shapes would clip. */
    property bool showImage: false

    /* Is there a picture to draw in it? */
    readonly property bool hasImage: showImage && imageSource !== ""

    /* Raw, because it decides the stock text's tone. */
    property real stock: 0
    property string stockText: ""
    property bool lowStock: false

    /* "transparent" means "no colour set" — a `color` property cannot be
       null, and a zero alpha is the one value that can never be a real
       choice. */
    property color accent: "transparent"
    readonly property bool tinted: accent.a > 0

    /* Room to keep clear at the trailing end of the NAME, for something the
       host draws over the card's top corner — the arrange screen's favourite
       star. */
    property int nameTrailingRoom: 0

    /* There is stock on the shelf. NOT "can be sold" — see the header. */
    readonly property bool inStock: stock > 0
    readonly property bool oversold: stock < 0

    /*
     * The stock's tone, and the whole of the tile's warning vocabulary.
     *
     *   below zero   danger — the count is already negative
     *   at zero      danger — the next sale makes it negative
     *   low          warning
     *   healthy      "" — plain secondary text, information not alarm
     */
    readonly property string stockTone: (oversold || stock === 0) ? "danger"
                                      : lowStock ? "warning" : ""

    // =====================================================================
    // BEHAVIOUR
    // =====================================================================
    hoverEnabled: true
    /* The card's height is its CONTENT's — never a token's guess at it:
       the image card is two name lines and one money line between the
       paddings (the words), and the photo matches whatever that is by
       spanning the card's full height — the merchant's rule, "height of
       image == height of card", with no strips of empty card above or
       below the picture. The text tile keeps its own fixed token. */
    implicitWidth: showImage ? Tokens.size.tileMediaMin : Tokens.size.tileMin
    implicitHeight: showImage
                    ? 2 * Tokens.spacing.sm + Tokens.size.tileName
                      + textFaceMoneyHeight
                    : Tokens.size.tile

    /* The tap landed. A 400ms emerald pulse on the border, so a wall of taps
       confirms each one without a dialog — the cart line flashing into
       selection below does the rest. */
    property bool added: false
    onAddedChanged: if (added) addedTimer.restart()

    Timer {
        id: addedTimer
        interval: 400
        onTriggered: tile.added = false
    }

    /* Padding is set here, once, rather than on each label — Control hands
       contentItem exactly the area between its paddings, so this is the single
       place the face's inset is decided.

       EQUAL ON ALL FOUR SIDES, by the merchant's own measure: the square and
       its words hold the same distance from every border, so a wall of cards
       reads as one grid whatever is in them. The product's colour stripe pays
       for that — it used to buy itself extra clearance on the leading edge,
       but the 3px stripe sits inside the border's radius inset and the
       content starts 12px in, so it keeps its key without taxing the pad. */
    topPadding: Tokens.spacing.sm
    bottomPadding: Tokens.spacing.sm
    leftPadding: Tokens.spacing.sm
    rightPadding: Tokens.spacing.sm

    Accessible.role: Accessible.Button
    Accessible.name: name
    Accessible.description: inStock
        ? priceText
        : Strings.t("pos.tile.out_of_stock", "Out of stock")

    /* Tooltip carries what will not fit on the face: the untruncated name,
       the barcode, and the stock in words. */
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

    /* Press feedback. A transform, so it costs the compositor nothing, and on
       a touchscreen it is the only confirmation that the tap landed. */
    scale: down ? 0.98 : 1.0
    Behavior on scale {
        NumberAnimation { duration: Fluent.anim.speed; easing.type: Easing.OutQuint }
    }

    // =====================================================================
    // SURFACE
    // =====================================================================
    background: Rectangle {
        radius: Tokens.radius.md

        /* Neutral card. No dead-grey state for zero stock — the tile stays a
           live, tappable product, and the stock text is what says so. Hover
           is the subtle fill; the resting card is plain white against the
           workspace canvas, which is what makes 60 of them read as a wall
           rather than as 60 outlined boxes. */
        color: tile.down ? Fluent.subtleTertiary
             : tile.hovered ? Fluent.subtleSecondary
                            : Tokens.workspace.surface

        border.width: 1
        /* The boundary carries the tile's states. Resting is the quiet
           structural border; hover strengthens it (a boundary, not just a
           wash, so the card the pointer is over is unmistakable); the
           400ms emerald flash confirms a tap; and the oversold outline is
           worth keeping from the old design — across a wall of tiles it is
           what carries, and a product already below zero is the one thing
           on this screen somebody may want to stop and check. */
        border.color: tile.added ? Tokens.brand
                  : tile.oversold
                      ? Qt.rgba(Tokens.danger.r, Tokens.danger.g,
                                Tokens.danger.b, 0.55)
                  : tile.hovered ? Fluent.controlBorderStrong
                                 : Tokens.workspace.border

        Behavior on border.color {
            ColorAnimation { duration: Fluent.anim.fast }
        }

        /* Leading-edge stripe in the product's colour — the merchant's sort
           key, three pixels wide. Inset top and bottom by the card's own
           radius: a rounded Rectangle clips to its bounding box rather than
           its arcs, so a full-height stripe would show a nub outside each
           corner. */
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: Tokens.radius.md
            anchors.bottomMargin: Tokens.radius.md
            width: 3
            radius: 2
            visible: tile.tinted
            color: tile.accent
        }

        // Keyboard focus. Drawn, not borrowed: AbstractButton has no style to
        // supply a focus ring.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: parent.radius + 2
            color: "transparent"
            border.width: 2
            border.color: Tokens.brand
            visible: tile.visualFocus
        }
    }

    // =====================================================================
    // FACE
    // =====================================================================
    /* Two faces, one visible: the horizontal image card and the text-first
       tile. The grid's `showImage` decides which — never the row, because
       a GridView has one cell size and a wall of mixed heights is a wall of
       clipped cards. Both faces fill the contentItem; the hidden one is
       simply not painted.

       THE MONEY BLOCK'S HEIGHT, shared by the card's height budget: one
       price line and the stock pill that may wrap under it on a narrow
       card — measured from the tokens, not from a laid-out child, so the
       card's implicit height is knowable before anything is instantiated. */
    readonly property int textFaceMoneyHeight:
        Math.round(Tokens.font.tilePrice * 1.35)
        + (Tokens.spacing.xs + Math.round(Tokens.font.caption * 1.4))

    contentItem: Item {

        // -- the image card ------------------------------------------------
        /* The photo is the card's own height, edge to edge: the square is
           anchored top and bottom to the CARD (not inset by the padding —
           that padding belongs to the words' column), so there is no empty
           strip above or below the picture. The words beside it are
           vertically CENTRED — the merchant's rule — rather than pushed to
           the edges of their column. */
        Item {
            id: square

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: height
            visible: tile.showImage

            /* An edge-to-edge plate, not a framed thumbnail: the photo runs
               into the card's very edges, which is what "height of image ==
               height of card" looks like — no border to eat a pixel row, no
               radius to lift a corner, no inset. */
            Rectangle {
                id: photoFrame

                anchors.fill: parent
                radius: 0
                clip: true

                /* A product WITH a photo gets the merchant's colour as the
                   plate's ground at low strength — the photo covers it, so
                   it is the plate that colour reads on. */
                color: tile.tinted
                       ? Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.10)
                       : Fluent.subtleTertiary
                border.width: 0

                Image {
                    anchors.fill: parent
                    visible: tile.hasImage
                    source: tile.hasImage ? tile.imageSource : ""
                    /* Aspect-fill and crop the overflow: a letterboxed photo
                       leaves grey bars on every card, and a stretched one
                       distorts the product. */
                    fillMode: Image.PreserveAspectCrop
                    /* Never on the GUI thread: a till that stutters while it
                       reads forty files off a disk is a till that misses
                       taps. */
                    asynchronous: true
                    /* Decoded at twice the square and no more. */
                    sourceSize.width: 2 * Tokens.size.tileImage
                    mipmap: true
                }

                /* The placeholder: a quiet package glyph on the same neutral
                   ground. Not an error symbol, not a pastel wash — a product
                   with no photo is ordinary, and the square it would have
                   occupied is part of the grid's rhythm. */
                Icon {
                    anchors.centerIn: parent
                    visible: !tile.hasImage
                    icon: "ic_fluent_box_20_regular"
                    size: Tokens.icon.md
                    color: Fluent.textTertiary
                }
            }
        }

        /* The words, to the trailing side of the square, vertically
           CENTRED: name and money as one block with air above and below,
           rather than a name pinned to the top of the card and a price
           pinned to the bottom of it. The block reads as one thing beside
           its picture. */
        ColumnLayout {
            id: words

            anchors.left: square.right
            anchors.leftMargin: tile.showImage ? Tokens.spacing.sm : 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: tile.showImage
            spacing: Tokens.spacing.xs

            /* The name, in a fixed two-line band: two lines of
               font.tileName is what the card's height was budgeted for,
               and a name that needs more than two lines ellipsises into
               the tooltip rather than eating the money block's room. */
            Text {
                Layout.fillWidth: true

                text: tile.name
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.tileName
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                /* Logical alignment: mirrors to AlignRight in Arabic. Pinned
                   rather than left to default because a Text with no explicit
                   alignment follows its OWN content's direction, which would
                   put a French-named product on the wrong edge of an Arabic
                   screen. */
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignTop
            }

            /* Price and stock. A Flow, not a Row: a wide card carries
               "1,017.13   Stock 70" on one line; a narrow one wraps the
               stock under the price automatically, which reads and stays
               labelled — the alternative was an ellipsis eating the count. */
            Flow {
                Layout.fillWidth: true

                spacing: Tokens.spacing.xs

                Text {
                    width: Math.min(implicitWidth, parent.width)
                    text: tile.priceText
                    font.pixelSize: Tokens.font.tilePrice
                    font.weight: Font.DemiBold
                    /* Tabular figures: a wall of prices in one column is only
                       comparable if the digits are one width. */
                    font.family: Tokens.font.family
                    font.features: Tokens.figures
                    color: Fluent.textPrimary
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                }

                StockPill { }
            }
        }

        // -- the text tile -------------------------------------------------
        /* The no-photo face: the compact card the wall has always had. Name
           to the top, price and stock to the bottom, slack in the middle
           where a one-line name should leave it. */
        Item {
            id: textFace

            anchors.fill: parent
            visible: !tile.showImage

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                /* Mirrors with the anchor: under LayoutMirroring `right` becomes
                   `left` and the margin travels with it, so the cleared corner is
                   the trailing one in Arabic too. */
                anchors.rightMargin: tile.nameTrailingRoom
                anchors.top: parent.top
                height: Tokens.size.tileName

                text: tile.name
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.tileName
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignTop
            }

            /* A Layout, so the stock claims its width and the price takes the
               rest, and so the pair swaps sides in Arabic without either of
               them being told to. */
            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: Tokens.spacing.sm

                Text {
                    Layout.fillWidth: true
                    text: tile.priceText
                    font.pixelSize: Tokens.font.tilePrice
                    font.weight: Font.DemiBold
                    font.family: Tokens.font.family
                    font.features: Tokens.figures
                    color: Fluent.textPrimary
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                }

                StockPill { }
            }
        }
    }

    /*
     * The stock, on every tile, and labelled: "Stock 24" rather than an
     * unexplained 24 — the number is only information once it says what it
     * counts. Plain secondary text while healthy — a labelled number on two
     * hundred tiles as a row of pills is noise — and a small tinted pill only
     * when the number is the news, with words in the pill rather than colour
     * alone.
     *
     * Declared once as a component and instantiated in both faces, because
     * the two faces are two shapes of the same card, not two cards.
     */
    component StockPill: Rectangle {
        id: stockPill

        readonly property bool alarmed: tile.stockTone !== ""

        width: stockLabel.implicitWidth + (alarmed ? Tokens.spacing.sm : 0)
        height: stockLabel.implicitHeight + (alarmed ? 2 : 0)
        radius: Tokens.radius.sm
        color: alarmed ? Tokens.toneFill(tile.stockTone) : "transparent"

        Text {
            id: stockLabel
            anchors.centerIn: parent
            /* Alarmed states say the situation in words; the healthy state
               says the count with its label. The number is always the real
               one — a product already at −3 must report −3, not zero. */
            text: tile.oversold
                  ? "\u200e" + (tile.stockText !== ""
                                ? tile.stockText : String(tile.stock))
                  : tile.stock === 0
                      ? Strings.t("pos.tile.out_of_stock", "Out of stock")
                      : Strings.t("pos.tile.stock", "Stock")
                        + " \u200e" + (tile.stockText !== ""
                                       ? tile.stockText : String(tile.stock))
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            font.weight: stockPill.alarmed ? Font.DemiBold : Font.Normal
            font.features: Tokens.figures
            color: stockPill.alarmed ? Tokens.toneInk(tile.stockTone)
                                     : Fluent.textSecondary
        }
    }
}
