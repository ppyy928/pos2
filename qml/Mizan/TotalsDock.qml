import QtQuick
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The totals dock: what this sale comes to, and the two ways to take the money.
 * Ported from pos/app/widgets/transaction.py::TransactionFooterBar in its `dock`
 * form, which pos shares between the till, purchases and returns.
 *
 *  ┌────────────────────────────────────────────────────────────────────────┐
 *  │ 🧾 Cart 001    │             TOTAL              │  ┌────────┐ ┌──────┐ │
 *  │ Items      4   │        12 480,00 DA            │  │ Cash   │ │Partial│ │
 *  │ Quantity   7   │                                │  │ F9     │ │F8    │ │
 *  │ Discount 200,00│                                │  └────────┘ └──────┘ │
 *  └────────────────────────────────────────────────────────────────────────┘
 *      metadata              the figure                   the decision
 *
 * The three zones are pos's, and the split is the point: operational facts on one
 * side, the money in the middle at a size that can be read standing up, and the
 * commitment on the far side where nothing else can be hit by accident.
 *
 * WHY IT STAYS DARK IN BOTH THEMES
 *
 * Same reason as the nav rail: it anchors the screen. It also makes the total the
 * brightest thing in the room, which is what it should be. Everything on it inks
 * from Tokens.onChrome* and Tokens.chromeHue*, never from the theme-switched
 * palette — a light-theme emerald on navy is unreadable, which is exactly the
 * trap Tokens keeps a separate chromeHue block to avoid.
 *
 * EVERY FIGURE ARRIVES FORMATTED
 *
 * Nothing here is a number. pos's fmt_money knows the currency, the decimal count
 * and the digit shapes for the active language, and a second implementation in
 * JavaScript would be a second set of rules for the same money. A line with an
 * empty string hides itself, which is how a sale with no discount shows no
 * discount line — pos passes None for the same purpose.
 */
Rectangle {
    id: dock

    // =====================================================================
    // API
    // =====================================================================
    property string cartNumber: ""
    property string itemsText: ""
    property string qtyText: ""
    property string discountText: ""

    /* The three captions on the metadata line, overridable.
     *
     * The till's third figure is a discount; a delivery's is what is still owed to the
     * supplier. Same slot, same shape, different word — so the word is a property
     * rather than a hard-coded key, and the defaults are what the till already said.
     */
    property string itemsCaption: Strings.t("pos.summary.items", "Items")
    property string qtyCaption: Strings.t("pos.summary.qty", "Quantity")
    property string discountCaption: Strings.t("pos.summary.discount", "Discount")

    property string totalText: "—"
    property string currencyText: ""

    /*
     * What has been paid on this document, and what is left. Empty on a document that
     * has not been settled yet — a NEW invoice has nothing paid, and a "Paid 0.00"
     * column on a blank form is a fake reading rather than an answer. `pos`'s purchase
     * footer hides the same two columns for the same reason.
     */
    property string paidText: ""
    property string remainingText: ""

    /* Whether the remaining figure is money still owed. The caller knows; the dock
       cannot tell from a formatted string, and "0.00" is good news rather than a
       warning. */
    property bool owing: false

    /* The payment heroes. A plain alias rather than the default property: a
       default property alias swallows every unnamed child, and this file's own
       layout is one of them. Same reason FilterBar names its slots. */
    property alias actionItems: actionHost.data

    // =====================================================================
    // SURFACE
    // =====================================================================
    implicitHeight: Tokens.size.dock
    radius: Tokens.radius.lg

    gradient: Gradient {
        GradientStop { position: 0.0; color: Tokens.dockFrom }
        GradientStop { position: 1.0; color: Tokens.dockTo }
    }

    /* A rim rather than a full border: the dock sits at the bottom of the screen
       against a light page, and one lighter line along the top edge is how this
       library builds depth — it has no shadow of any kind. */
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.radius.lg
        height: 1
        color: Tokens.chromeBorder
    }

    // =====================================================================
    // METADATA LINE
    // =====================================================================
    /* Caption and value as two Texts rather than one interpolated string: the
       caption is quiet and the value is not, and a translator cannot break a
       layout that has no placeholder in it. */
    component MetaLine: Row {
        id: meta
        property string caption: ""
        property string value: ""

        visible: value !== ""
        spacing: Tokens.spacing.xs

        Text {
            text: meta.caption
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: Tokens.onChromeMuted
        }

        Text {
            /* U+200E: a count or an amount inside an Arabic paragraph is
               reordered without it. */
            text: "\u200e" + meta.value
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            font.weight: Font.DemiBold
            color: Tokens.onChrome
        }
    }

    /* A read-only money column: a quiet caption over a loud figure. Two Texts rather
       than one interpolated string, for the reason MetaLine gives — and at body-large
       rather than caption size, because these sit beside a 64px total and a 12px line
       there reads as a footnote instead of a figure. */
    component Figure: ColumnLayout {
        id: money
        property string caption: ""
        property string value: ""
        property color ink: Tokens.onChrome

        visible: value !== ""
        spacing: 0

        Text {
            text: money.caption
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.overline
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.1
            color: Tokens.onChromeMuted
        }

        Text {
            text: "\u200e" + money.value
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.bodyLarge
            font.features: Tokens.figures
            font.weight: Font.DemiBold
            color: money.ink
        }
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.size.cardPadding
        spacing: Tokens.spacing.xl

        // -----------------------------------------------------------------
        // zone M — what this cart is
        // -----------------------------------------------------------------
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacing.xs

            Row {
                visible: dock.cartNumber !== ""
                spacing: Tokens.spacing.xs

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "ic_fluent_receipt_money_20_regular"
                    size: Tokens.icon.sm
                    color: Tokens.onChromeMuted
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u200e" + dock.cartNumber
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    font.weight: Font.DemiBold
                    color: Tokens.onChrome
                }
            }

            MetaLine {
                caption: dock.itemsCaption
                value: dock.itemsText
            }

            MetaLine {
                caption: dock.qtyCaption
                value: dock.qtyText
            }

            MetaLine {
                caption: dock.discountCaption
                value: dock.discountText
            }
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.topMargin: Tokens.spacing.xs
            Layout.bottomMargin: Tokens.spacing.xs
            implicitWidth: 1
            color: Tokens.chromeBorder
        }

        // -----------------------------------------------------------------
        // zone T — the figure
        // -----------------------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Strings.t("pos.summary.total", "Total")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.overline
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2
                color: Tokens.onChromeMuted
            }

            /* The amount and its currency as one baseline-aligned pair, the way
               pos composes them: 64px for the number, ordinary body size for the
               currency, so the figure is what carries across the shop and the
               currency is merely present.

               Anchored inside a plain Item rather than stacked in a Row, because
               a Row is a positioner and refuses the vertical anchor this needs —
               and bottom-aligning two boxes 43px apart in size is not the same
               thing as sharing a baseline. Anchors mirror, so the currency
               follows the number in Arabic too. */
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: figure.implicitWidth
                               + (currency.visible
                                  ? currency.implicitWidth + Tokens.spacing.xs : 0)
                implicitHeight: figure.implicitHeight

                Text {
                    id: figure
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: "\u200e" + dock.totalText
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.posTotal
                    /* Tabular figures. At 64px this is the largest number in the
                       product and the one an operator reads aloud to a customer;
                       proportional digits make it slide sideways as the cart grows,
                       because a 1 is 40% narrower than a 0 in this typeface. */
                    font.features: Tokens.figures
                    font.weight: Font.DemiBold
                    /* Tuned for this navy specifically — plain emerald fails
                       contrast on it, and this is the pair Tokens keeps for the
                       purpose. */
                    color: Tokens.onChromeSuccess
                }

                Text {
                    id: currency
                    anchors.left: figure.right
                    anchors.leftMargin: Tokens.spacing.xs
                    anchors.baseline: figure.baseline
                    visible: dock.currencyText !== ""
                    text: dock.currencyText
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.bodyLarge
                    font.weight: Font.DemiBold
                    color: Tokens.onChromeMuted
                }
            }
        }

        // -----------------------------------------------------------------
        // zone F — what has been settled, on a document that has been settled
        // -----------------------------------------------------------------
        /*
         * Two read-only figures beside the total: what was paid and what is left.
         *
         * `pos`'s purchase footer draws the same three columns and hides the last two
         * on a NEW document — there is nothing paid on an invoice that does not exist
         * yet, and a "Paid 0.00" column on a blank form is a fake reading. So these
         * appear only when the caller supplies them, and the caller supplies them only
         * when it is editing.
         *
         * They were tried as caption lines in zone M and it was the wrong weight: an
         * operator settling an invoice with a rep is reading "how much is left", and a
         * 12px grey line under "1 lines" is not where anybody looks for that.
         */
        Rectangle {
            Layout.fillHeight: true
            Layout.topMargin: Tokens.spacing.xs
            Layout.bottomMargin: Tokens.spacing.xs
            visible: dock.paidText !== "" || dock.remainingText !== ""
            implicitWidth: 1
            color: Tokens.chromeBorder
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            visible: dock.paidText !== "" || dock.remainingText !== ""
            spacing: Tokens.spacing.xs

            Figure {
                caption: Strings.t("invoice.paid", "Paid")
                value: dock.paidText
                ink: Tokens.onChrome
            }

            Figure {
                caption: Strings.t("invoice.fin.remaining", "Remaining")
                value: dock.remainingText
                /* Red only when something is actually owed: a settled invoice's zero is
                   good news and colouring it as a warning would teach the operator to
                   ignore the colour. */
                ink: dock.owing ? Tokens.onChromeDanger : Tokens.onChromeSuccess
            }
        }

        // -----------------------------------------------------------------
        // zone A — the decision
        // -----------------------------------------------------------------
        Row {
            id: actionHost
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacing.sm
        }
    }
}
