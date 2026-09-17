import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * One line in the till's cart. Ported from
 * pos/app/widgets/cart_list.py::CartLineItem.
 *
 *     ┌────────────────────────────────────────────────────────────┐
 *     │ Coca-Cola 1.5L                                   240,00     │
 *     │ 120,00                [ −  2  + ]            🗑             │
 *     └────────────────────────────────────────────────────────────┘
 *
 * TWO LINES, AT 78PX
 *
 * The row used to stack name over stepper and print the line total at 34px —
 * the size of the transaction total itself — beside it. The line is one of
 * six on the screen and the total is the one that is owed, so the line's own
 * figure now sits on the FIRST line at 19px, right-aligned and tabular, and
 * the second line is the unit price with the stepper. 78px against the old
 * 88 puts a fifth sale line on screen without shrinking the 48px stepper
 * floor underneath.
 *
 * WHY THE STEPPER SITS ON THE ROW
 *
 * pos changes a quantity by selecting the line and retyping it on the numpad, or
 * by opening a small editor over the row. A −/+ pair on the line itself is the
 * biggest touch win available on this screen, and it is what sets
 * Tokens.size.cartRow: a 48px control cannot live in a 56px table row, so the
 * cart is a list of cards rather than a table.
 *
 * WHY REMOVE IS SEPARATED FROM THE STEPPER
 *
 * The bin is one deliberate tap-width clear of the +: the + is struck a
 * hundred times a sale, the bin once, and a mis-tap on the second must not
 * undo the first. It still has the destructive red ink, and the full name is
 * in the tooltip before it goes.
 *
 * WHY THIS ROW MIRRORS AND pos's DOES NOT
 *
 * cart_list.py pins the row to LeftToRight so its four pieces never move. Here
 * the row is a Layout and mirrors with the language, because every other surface
 * in this app does — a cart that reads left-to-right inside an Arabic screen is
 * the one row that looks broken. Nothing is lost by mirroring: the amounts
 * arrive already formatted from Python, which owns the digit shapes for the
 * active language.
 *
 * THE ARITHMETIC IS NOT HERE
 *
 * The stepper reports the quantity it *wants*; it never sets one. The cart is
 * owned by the controller, the totals are computed and formatted there, and a
 * row that changed its own number before the total under it agreed would be
 * worse than a tap that is refused. Same one-way rule as NavRail and Numpad.
 */
Rectangle {
    id: line

    // =====================================================================
    // API
    // =====================================================================
    property string name: ""

    /* Unit price and line total, both formatted by pos's fmt_money. The row
       shows no currency symbol — pos drops it here too, so a column of six
       amounts stays quiet and the currency appears once, on the dock. */
    property string priceText: ""
    property string totalText: ""

    /* The quantity as text, because that is what is displayed, and as a number,
       because the stepper has to add to it. Both come from the controller: one
       is fmt_qty's output, the other the raw value behind it. */
    property string qtyText: ""
    property real qty: 0

    /* The step is the product's own unit quantity — a 6-pack steps by 6 if the
       catalogue says so. pos passes the same value into the card. */
    property real step: 1

    property bool selected: false

    signal clicked()
    signal qtyRequested(real value)
    signal removeRequested()

    // =====================================================================
    // SURFACE
    // =====================================================================
    implicitHeight: Tokens.size.cartRow
    radius: Tokens.radius.md

    /* Selected is a fill, not a border: a 1px outline appearing and disappearing
       shifts nothing but is easy to miss across a counter, and the brand tint is
       legible at arm's length. Hover is the ordinary subtle fill so a mouse user
       still gets the row they are about to hit. */
    color: selected ? Tokens.brandTint
         : hover.hovered ? Fluent.subtleSecondary
                         : "transparent"
    Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }

    /* Leading marker for the selected line. The keypad's Qty entry acts on this
       row and nothing else, so which row it is has to be unmistakable. Inset by
       the radius for the same reason PosTile's stripe is: a rounded Rectangle
       clips to its bounding box, not to its arcs. */
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: Tokens.radius.md
        anchors.bottomMargin: Tokens.radius.md
        width: 3
        radius: 2
        visible: line.selected
        color: Tokens.brand
    }

    /* The light separator between rows. The list's spacing is zero now — a
       hairline is the separation, so five rows fit where four did — and it
       stays under the selected row too: emerald above, hairline below, the
       next line still reads as the next line. */
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Fluent.dividerBorder
        opacity: line.selected ? 0.35 : 0.7
    }

    HoverHandler { id: hover }

    /* Tapping the row selects it. The buttons inside accept their own presses,
       so the stepper and the bin do not also move the selection — which is what
       pos gets from putting this on mousePressEvent. */
    TapHandler {
        onTapped: line.clicked()
    }

    Accessible.role: Accessible.ListItem
    Accessible.name: line.name
    Accessible.description: line.totalText

    // =====================================================================
    // CONTENT
    // =====================================================================
    /* Both content lines run to the same trailing edge, so the line total
       right-aligns over the Remove button and the amounts column reads as a
       column. Anchored to the sides and centred vertically — the row's height
       is the stepper's at normal text and grows with the text size, and the
       slack belongs half above and half below rather than all at the
       bottom. */
    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Tokens.spacing.sm
        /* The scrollbar's seat, spent here rather than on the ListView: the
           Fluent bar is an overlay inside the view's trailing edge, so a
           view-level margin moves the rows AND the bar together and the
           widened 12px bar still lands on these figures — the line totals
           sit on this edge, six of them in a column. The row pays the seat
           out of its own trailing padding instead, and the bar glides over
           clear row surface beside them. */
        anchors.rightMargin: Tokens.spacing.xs + Tokens.size.scrollSeat
        spacing: 2

        // -- the name, with the line's own figure on the same line --------
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.sm

            Text {
                Layout.fillWidth: true
                text: line.name
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
                elide: Text.ElideRight
                /* One line, elided. The untruncated name is in the tooltip,
                   and the row cannot grow: the stepper under it has a fixed
                   home. */
                maximumLineCount: 1
                horizontalAlignment: Text.AlignLeft
            }

            /* The line total: prominent at arm's length, subordinate to the
               transaction total under it, tabular so six of them line up. */
            Text {
                Layout.minimumWidth: 88
                Layout.alignment: Qt.AlignVCenter
                text: line.totalText
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.lineTotal
                font.weight: Font.DemiBold
                font.features: Tokens.figures
                color: Fluent.textPrimary
                elide: Text.ElideRight
                /* Trailing edge, logically: mirrors to the left in Arabic, where
                   the row's trailing edge is. */
                horizontalAlignment: Text.AlignRight
            }
        }

        // -- the unit price, the stepper, and Remove ----------------------
        RowLayout {
            Layout.fillWidth: true
            /* xs, not sm: this row's budget is the stepper's 148px plus the
               bin's 48px plus a gap each, and the price needs what is left —
               on a short window's narrower cart, sm was the difference
               between a price and an ellipsis. */
            spacing: Tokens.spacing.xs

            Text {
                text: line.priceText
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Fluent.textSecondary
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
            }

            Item { Layout.fillWidth: true }

            // -------------------------------------------------------------
            // stepper
            // -------------------------------------------------------------
            /* − field + reads in that order in both directions: a Row
                positions by x and reverses under the LayoutMirroring the
                window installs, so "less" stays on the leading edge in
                Arabic without being told. */
            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "ic_fluent_subtract_20_regular"
                    glyphSize: Tokens.icon.sm
                    /* Refusing the tap that would take the line to zero,
                       rather than sending a value the page has to reject.
                       Removing a line is the bin's job, and it is one tap
                       away. */
                    enabled: line.qty - line.step > 0
                    tooltip: Strings.t("cart.qty.decrease", "Less")
                    onClicked: line.qtyRequested(line.qty - line.step)
                }

                /* Editable, because a cashier with a keyboard changes "1" to
                   "12" faster than they tap + eleven times. The keypad's Qty
                   entry is the touch path to the same value.

                   Taking focus also selects the row — the field and the
                   keypad's readout must name the same line, or the number
                   being typed has no target.

                   No binding on `text`: a TextField assigns its own text as
                   the operator types, which would destroy one — so the value
                   is pushed in from onQtyTextChanged below, which is the only
                   other place it can change. Same reason ProductsPage sets
                   ComboBox.currentIndex by hand. */
                NumberField {
                    id: qtyField
                    anchors.verticalCenter: parent.verticalCenter
                    width: 72
                    height: Tokens.size.control
                    horizontalAlignment: TextInput.AlignHCenter
                    font.pixelSize: Tokens.font.body
                    font.weight: Font.DemiBold

                    Component.onCompleted: text = line.qtyText

                    onActiveFocusChanged: if (activeFocus) line.clicked()
                    onAccepted: line.commitTyped(text)
                    /* Also on focus loss: a cashier who types 3 and then taps
                       a product instead of pressing Enter meant 3. */
                    onEditingFinished: line.commitTyped(text)
                }

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "ic_fluent_add_20_regular"
                    glyphSize: Tokens.icon.sm
                    tooltip: Strings.t("cart.qty.increase", "More")
                    onClicked: line.qtyRequested(line.qty + line.step)
                }
            }

            /*
             * Remove, at the trailing edge and a full gap clear of the +: the
             * widest tap target on the row is the one next to it, and a slip
             * onto the bin costs a scan of the same product to undo. Red ink
             * only — the surface stays the row's own, so it does not compete
             * with the stepper it sits beside. The tooltip and the accessible
             * name say the whole act, not just the glyph.
             */
            IconButton {
                Layout.alignment: Qt.AlignVCenter
                /* A deliberate extra half-gap, so the bin clears the + by a
                   full tap-width while the row keeps its tight budget. */
                Layout.leftMargin: Tokens.spacing.xs
                glyph: "ic_fluent_delete_20_regular"
                glyphSize: Tokens.icon.sm
                glyphColor: Tokens.danger
                tooltip: Strings.t("cart.remove_item", "Remove item")
                onClicked: line.removeRequested()
            }
        }
    }

    // =====================================================================
    // BEHAVIOUR
    // =====================================================================
    /* Push a new quantity into the field. The delegate is recycled as the list
       scrolls and rebuilt when the cart changes, so this is also what keeps a
       field the operator typed into in step with the cart behind it. */
    onQtyTextChanged: qtyField.text = qtyText

    QC.ToolTip.text: line.name
    QC.ToolTip.visible: hover.hovered && line.name !== ""
    QC.ToolTip.delay: 700

    /* Parse what was typed and ask for it, or put the stored value back.
       "1,5" is what a French or Arabic keyboard produces for one and a half,
       and parseFloat stops at the comma — so the separator is normalised here. The
       digit *shapes* are Python's job: normalize_digits already handles
       Arabic-Indic input on the way in, and this field is the keyboard shortcut
       to a value the numpad can also set. */
    function commitTyped(text) {
        var value = parseFloat(String(text).replace(",", "."))
        if (isNaN(value) || value <= 0) {
            qtyField.text = line.qtyText
            return
        }
        if (value !== line.qty)
            line.qtyRequested(value)
    }
}
